{-# OPTIONS_GHC -Wno-compat-unqualified-imports #-}

-- We don't want to warn about duplicate exports for things exported
-- by both "module" exports
module T4478 (module Prelude, module Data.Foldable) where

import Prelude
import Data.Foldable
