{-# LANGUAGE TypeFamilies #-}
-----------------------------------------------------------------------------
-- |
-- Module     : Hadrian.Oracles.TextFile
-- Copyright  : (c) Andrey Mokhov 2014-2018
-- License    : MIT (see the file LICENSE)
-- Maintainer : andrey.mokhov@gmail.com
-- Stability  : experimental
--
-- Read and parse text files, tracking their contents. This oracle can be used
-- to read configuration or package metadata files and cache the parsing.
-----------------------------------------------------------------------------
module Hadrian.Oracles.TextFile (
    lookupValue, lookupValueOrEmpty, lookupValueOrError, lookupSystemConfig, lookupValues,
    lookupValuesOrEmpty, lookupValuesOrError, lookupDependencies, textFileOracle
    ) where

import Control.Monad
import qualified Data.HashMap.Strict as Map
import Data.Maybe
import Data.List
import Development.Shake
import Development.Shake.Classes
import Development.Shake.Config
import Base

import Hadrian.Utilities

-- | Lookup a value in a text file, tracking the result. Each line of the file
-- is expected to have @key = value@ format.
lookupValue :: FilePath -> String -> Action (Maybe String)
lookupValue file key = askOracle $ KeyValue (file, key)

-- | Like 'lookupValue' but returns the empty string if the key is not found.
lookupValueOrEmpty :: FilePath -> String -> Action String
lookupValueOrEmpty file key = fromMaybe "" <$> lookupValue file key

-- | Like 'lookupValue' but raises an error if the key is not found.
lookupValueOrError :: Maybe String -> FilePath -> String -> Action String
lookupValueOrError helper file key = fromMaybe (error msg) <$> lookupValue file key
  where
    msg = unlines $ ["Key " ++ quote key ++ " not found in file " ++ quote file]
                    ++ maybeToList helper

lookupSystemConfig :: String -> Action String
lookupSystemConfig = lookupValueOrError (Just configError) configFile
  where
    configError = "Perhaps you need to rerun ./configure"

-- | Lookup a list of values in a text file, tracking the result. Each line of
-- the file is expected to have @key value1 value2 ...@ format.
lookupValues :: FilePath -> String -> Action (Maybe [String])
lookupValues file key = askOracle $ KeyValues (file, key)

-- | Like 'lookupValues' but returns the empty list if the key is not found.
lookupValuesOrEmpty :: FilePath -> String -> Action [String]
lookupValuesOrEmpty file key = fromMaybe [] <$> lookupValues file key

-- | Like 'lookupValues' but raises an error if the key is not found.
lookupValuesOrError :: FilePath -> String -> Action [String]
lookupValuesOrError file key = fromMaybe (error msg) <$> lookupValues file key
  where
    msg = "Key " ++ quote key ++ " not found in file " ++ quote file

-- | The 'Action' @lookupDependencies depFile file@ looks up dependencies of a
-- @file@ in a (typically generated) dependency file @depFile@. The action
-- returns a pair @(source, files)@, such that the @file@ can be produced by
-- compiling @source@, which in turn also depends on a number of other @files@.
lookupDependencies :: FilePath -> FilePath -> Action (FilePath, [FilePath])
lookupDependencies depFile file = do
    let -- .hs needs to come before .hi-boot deps added to fix #14482.
        -- This is still a bit fragile: we have no order guaranty from the input
        -- file. Let's hope we don't have two different .hs source files (e.g.
        -- one included into the other)...
        weigh p
          | ".hs" `isSuffixOf` p = 0 :: Int
          | otherwise            = 1
    deps <- fmap (sortOn weigh) <$> lookupValues depFile file
    case deps of
        Nothing -> error $ "No dependencies found for file " ++ quote file
        Just [] -> error $ "No source file found for file " ++ quote file
        Just (source : files) -> return (source, files)

newtype KeyValue = KeyValue (FilePath, String)
    deriving (Binary, Eq, Hashable, NFData, Show, Typeable)
type instance RuleResult KeyValue = Maybe String

newtype KeyValues = KeyValues (FilePath, String)
    deriving (Binary, Eq, Hashable, NFData, Show, Typeable)
type instance RuleResult KeyValues = Maybe [String]

-- | These oracle rules are used to cache and track answers to the following
-- queries, which are implemented by parsing text files:
--
-- 1) Looking up key-value pairs formatted as @key = value1 value2 ...@ that
--    are often used in text configuration files. See functions 'lookupValue',
--    'lookupValueOrEmpty', 'lookupValueOrError', 'lookupValues',
--    'lookupValuesOrEmpty' and 'lookupValuesOrError'.
--
-- 2) Parsing Makefile dependency files generated by commands like @gcc -MM@:
--    see 'lookupDependencies'.
textFileOracle :: Rules ()
textFileOracle = do
    kv <- newCache $ \file -> do
        need [file]
        putVerbose $ "| KeyValue oracle: reading " ++ quote file ++ "..."
        liftIO $ readConfigFile file
    void $ addOracleCache $ \(KeyValue (file, key)) -> Map.lookup key <$> kv file

    kvs <- newCache $ \file -> do
        need [file]
        putVerbose $ "| KeyValues oracle: reading " ++ quote file ++ "..."
        contents <- map words <$> readFileLines file
        return $ Map.fromList [ (key, values) | (key:values) <- contents ]
    void $ addOracleCache $ \(KeyValues (file, key)) -> Map.lookup key <$> kvs file
