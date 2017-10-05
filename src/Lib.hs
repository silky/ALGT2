module Lib
    ( someFunc
    ) where

import Utils.All

import Assets
import AssetUtils

import LanguageDef.Data.LanguageDef
import LanguageDef.ModuleLoader	
import LanguageDef.Data.Function
import LanguageDef.Data.Expression 
import LanguageDef.Utils.LocationInfo
import LanguageDef.Interpreter


import LanguageDef.API
import LanguageDef.LangDefs



import Data.Map as M


import Utils.Version

someFunc :: IO ()
someFunc = putStrLn versionString
