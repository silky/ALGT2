{-# LANGUAGE TemplateHaskell #-}
module LanguageDef.Scope where


import Utils.All
import Data.Map (Map)
import Data.Map as M


{- 
Represents a module scope, with elements of this module that are imported, exported and all relevant stuff
Arguments: 
name: The fully qualified names of modules, globally distinguishable
nameInt: the internal name for modules, as seen from inside (this allows renames, such as `import Data.Map as M`
a: the thing that is exported/imported by the module, the module contents. This will often be some data structure
importFlags: extra information about the imports, such as qualified imports and such
 -}
data Scope name nameInt a importFlags exportFlags = Scope
	{ _scopeName		:: name		-- The fully qualified scope name, as how it is called by the outside world
	, _imported		:: Map name (a, importFlags)	-- The fully qualified names of other scopes that are imported, and stuff that it imports. Flags might indicate extra information, such as qualified imports etc...
	, _importedInternalView	:: Map nameInt name	-- The internal view; sometimes modules are referred differently internally
	, _payload		:: a		-- The stuff that this module defines to the outside world, the actual payload
	, _reExports		:: Map name exportFlags	-- The stuff that is imported and reexported from other modules
	} deriving (Show, Eq, Ord)
makeLenses ''Scope


-- Gets an explicit import, based on the internal name
explicitImport	:: (Ord nameInt, Ord name) => (name -> String) -> (nameInt -> String) -> Scope name nameInt a flags eflags -> nameInt -> Either String (name, a, flags)
explicitImport showName showNameInt scope nameInt
	= do	let scopeNm	= showName (get scopeName scope)	:: String
		let msg		= "The namespace "++showNameInt nameInt++" is not available within scope "++ scopeNm ++"; try importing it"
		explicitName	<- checkExistsSugg showNameInt nameInt (get importedInternalView scope) msg
		let msg'	= "The fully qualified namespace "++showName explicitName++" is not available within scope "++ scopeNm ++"; this is probably a bug"
		(a, flags)	<- checkExistsSugg showName explicitName (get imported scope) msg'
		return (explicitName, a, flags)



-- Updates all 'import' references of each scope by the one in the dictionary
knotScopes	:: (Ord name) => (name -> String) -> Map name (Scope name ni a ifl efl) -> Map name (Scope name ni a ifl efl)
knotScopes showName scopes
	= let 	scopes'	=  scopes |> (_knotScope showName scopes') in	-- I _love_ lazyness
		scopes'

_knotScope	:: (Ord name) => (name -> String) -> Map name (Scope name ni a ifl efl) -> Scope name ni a ifl efl -> Scope name ni a ifl efl
_knotScope showName scopes scopeToFix
	= let	find nm		= checkExists nm scopes ("Bug: "++showName nm++" missing in the already fixed") & either error (get payload)
		imported'	= get imported scopeToFix & M.mapWithKey 
					(\nm (_, flags) -> (find nm, flags))
		in
		scopeToFix & set imported imported'
