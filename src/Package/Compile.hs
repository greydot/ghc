{-# LANGUAGE NoImplicitPrelude #-}
module Package.Compile (buildPackageCompile) where

import Package.Base
import Development.Shake.Util

argListDir :: FilePath
argListDir = "shake/arg/buildPackageCompile"

suffixArgs :: Way -> Args
suffixArgs way = arg ["-hisuf", hisuf way]
              <> arg [ "-osuf",  osuf way]
              <> arg ["-hcsuf", hcsuf way]

ghcArgs :: Package -> TodoItem -> Way -> [FilePath] -> FilePath -> Args
ghcArgs (Package _ path _) (stage, dist, _) way srcs result =
    let buildDir = toStandard $ path </> dist </> "build"
        pkgData  = path </> dist </> "package-data.mk"
    in suffixArgs way
    <> wayHcArgs way
    <> arg SrcHcOpts
    <> packageArgs stage pkgData
    <> includeArgs path dist
    <> concatArgs ["-optP"] (CppOpts pkgData)
    <> arg (HsOpts pkgData)
    -- TODO: now we have both -O and -O2
    -- <> arg ["-O2"]
    <> productArgs ["-odir", "-hidir", "-stubdir"] buildDir
    <> when (splitObjects stage) (arg "-split-objs")
    <> arg ("-c":srcs)
    <> arg ["-o", result]

buildRule :: Package -> TodoItem -> Rules ()
buildRule pkg @ (Package name path _) todo @ (stage, dist, _) =
    let buildDir = toStandard $ path </> dist </> "build"
        depFile  = buildDir </> takeBaseName name <.> "m"
    in
    [buildDir <//> "*o", buildDir <//> "*hi"] &%> \[out, _] -> do
        let way  = detectWay $ tail $ takeExtension out
        need [argListPath argListDir pkg stage, depFile]
        depContents <- parseMakefile <$> (liftIO $ readFile depFile)
        let deps = concat $ snd $ unzip $ filter ((== out) . fst) depContents
            srcs = filter ("//*hs" ?==) deps -- TODO: handle *.c sources
        need deps
        terseRun (Ghc stage) $ ghcArgs pkg todo way srcs (toStandard out)

argListRule :: Package -> TodoItem -> Rules ()
argListRule pkg todo @ (stage, _, settings) =
    (argListPath argListDir pkg stage) %> \out -> do
        need $ ["shake/src/Package/Compile.hs"] ++ sourceDependecies
        ways' <- ways settings
        ghcList <- forM ways' $ \way ->
            argList (Ghc stage)
                (ghcArgs pkg todo way ["input.hs"] $ "output" <.> osuf way)
                $ "way '" ++ tag way ++ "'"
        writeFileChanged out $ unlines ghcList

buildPackageCompile :: Package -> TodoItem -> Rules ()
buildPackageCompile = argListRule <> buildRule
