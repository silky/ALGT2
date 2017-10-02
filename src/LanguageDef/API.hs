module LanguageDef.API 
		(loadLangDef, loadLangDef', loadAssetLangDef, loadAssetLangDef'
		, createParseTree, createExpression, createTypedExpression, parseTarget
		, LangDefs.resolveGlobal, LangDefs.resolve, LangDefs.resolve', LangDefs.allKnowns
		, LangDefs.syntaxCall, LangDefs.functionCall, LangDefs.ruleCall, LangDefs.relationCall
		, resolveGlobal'
		, infoAbout, inScope, infoImports
		, testLanguage, testLanguage'
		, runFunction, runExpression, runExpression'
		, typeTop, typeBottom) where

{- 

Creates all kinds of stuff based on strings, to test with, such as expressions of functions, parsetrees, ...

This should all be based on some syntax

 -}

import Utils.All
import Utils.PureIO

import AssetUtils

import LanguageDef.ExceptionInfo
import LanguageDef.LanguageDef
import LanguageDef.LocationInfo
import LanguageDef.Scope

import LanguageDef.Syntax.All as Syntax
import qualified LanguageDef.Syntax.Combiner as Combiner

import LanguageDef.Expression
import LanguageDef.Function
import LanguageDef.Rule
import LanguageDef.Relation (predicate)
import LanguageDef.Typer
import LanguageDef.Interpreter (resolveAndRun', constructParseTree)

import LanguageDef.LangDefs (LangDefs)
import LanguageDef.ModuleLoader

import LanguageDef.LangDefs as LangDefs
import LanguageDef.LangDefsFix as LDF

import Data.Maybe

import Data.Map (Map, (!), empty)

{- Loads a language definition from the filesystem; use with 'runIO'-}
loadLangDef :: FilePath -> [Name] -> PureIO LangDefs
loadLangDef	= loadAll

loadLangDef'	:: FilePath -> [Name] -> PureIO LDScope
loadLangDef' fp fq
		= loadLangDef fp fq |> get langdefs |> (! fq)

{- Loads a language definition directly from the assets; is Pure -}
loadAssetLangDef	:: FilePath -> [Name] -> Either String LangDefs
loadAssetLangDef fp names
		= runPure allAssets' (loadLangDef fp names) |> fst

loadAssetLangDef'	:: FilePath -> [Name] -> Either String LDScope
loadAssetLangDef' fp names
		= loadAssetLangDef fp names |> get langdefs |> (! names)



testLanguage	= _testLanguage loadAssetLangDef
testLanguage'	= _testLanguage loadAssetLangDef' 

_testLanguage	:: (FilePath -> [Name] -> Either String a) -> a
_testLanguage loadWith
		= loadWith "" ["TestLanguage"] & either error id

{- | Gives info about any entry, resolved globally
>>> infoAbout testLanguage ["TestLanguage", "bool"] |> uncurry toParsable' & unlines
"\n TestLanguage.bool (Syntactic Form) \n====================================\n\n\n\nbool\t::=\"True\"\t\n\t | \"False\"\t\n\n"


>>> infoAbout testLanguage ["TestLanguage", "and"] |> uncurry toParsable' & unlines
"\n TestLanguage.and (Function) \n=============================\n\n\nand\t : TestLanguage.bool \215 TestLanguage.bool \8594 TestLanguage.bool\nand(\"True\", \"True\")\t = \"True\"\nand(_, _)\t = \"False\"\n\n\n\n TestLanguage.and (Rule) \n=========================\n\n\n \n---------------------------------------------- [ and ]\n (TestLanguage.\8594) (\"True\" \"&\" \"True\"), \"True\"\n\n\n"
>>> infoAbout testLanguage ["TestLanguage"]|> uncurry toParsable' & unlines
"\n TestLanguage (Language Definition) \n====================================\n\n# Blabla\n# \n Test Language \n***************\n\n# Blabla\n\n\n Syntax \n========\n\n\n\nbool\t::=\"True\"\t\n\t | \"False\"\t\n\n\nint\t::=Number\t\n\n\nexpr\t::=TestLanguage.bool\t\n\t | TestLanguage.int\t\n\n\nexprSum\t::=TestLanguage.expr TestLanguage.op TestLanguage.exprSum\t\n\t | TestLanguage.expr\t\n\n\nop\t::=\"&\"\t\n\t | \"+\"\t\n\n\ntuple\t::=TestLanguage.expr TestLanguage.expr\t\n\n\n\n Functions \n===========\n\n# Inverts a boolean\n# \nnot\t : TestLanguage.bool \8594 TestLanguage.bool\nnot(\"True\")\t = \"False\"\nnot(\"False\")\t = \"True\"\n\n\nand\t : TestLanguage.bool \215 TestLanguage.bool \8594 TestLanguage.bool\nand(\"True\", \"True\")\t = \"True\"\nand(_, _)\t = \"False\"\n\n\nnand\t : TestLanguage.bool \215 TestLanguage.bool \8594 TestLanguage.bool\nnand(a, b)\t = TestLanguage.not(TestLanguage.and(a, b))\n\n\nor\t : TestLanguage.bool \215 TestLanguage.bool \8594 TestLanguage.bool\nor(TestLanguage.not(\"True\"), TestLanguage.not(\"True\"))\t = \"False\"\nor(_, _)\t = \"True\"\n\n\n\n\n Relations \n===========\n\n\n(\8594)\tTestLanguage.exprSum (in) \215 TestLanguage.exprSum (out); Pronounced as \"smallstep\"\n\n\n\n\n Rules \n=======\n\n\n \n---------------------------------------------- [ and ]\n (TestLanguage.\8594) (\"True\" \"&\" \"True\"), \"True\"\n\n\n\n\n\n\n"

>>> infoAbout testLanguage ["~"]
[]


>>> infoAbout testLanguage ["TestLanguage", "→"] |> uncurry toParsable' & unlines
"\n TestLanguage.\8594 (Relation) \n===========================\n\n\n(\8594)\tTestLanguage.exprSum (in) \215 TestLanguage.exprSum (out); Pronounced as \"smallstep\"\n\n\n"

-}
infoAbout	:: LangDefs -> [Name] -> [(FQName, AllInfo)]
infoAbout langDefs names
	= let	fqn	= (init names, last names)
		ld	= langDef langDefs names |> getInfo |> ((,) fqn)
		search x	= resolveGlobal langDefs x fqn & either (const Nothing)  (\(fqn, e) -> Just (fqn, getInfo e))
		in
		catMaybes [ld, search syntaxCall, search functionCall, search relationCall, search ruleCall]

{- | Gives info about any entry, resolved from within the module. An entity could be not in scope or could be info about an import
>>> infoAbout' testLanguage' ["TestLanguage", "bool"] |> uncurry toParsable' & unlines
"\n TestLanguage.bool (Syntactic Form) \n====================================\n\n\n\nbool\t::=\"True\"\t\n\t | \"False\"\t\n\n"
>>> infoAbout' testLanguage' ["bool"] |> uncurry toParsable' & unlines
"\n TestLanguage.bool (Syntactic Form) \n====================================\n\n\n\nbool\t::=\"True\"\t\n\t | \"False\"\t\n\n"
>>> infoAbout' testLanguage' ["and"] |> uncurry toParsable' & unlines
"\n TestLanguage.and (Function) \n=============================\n\n\nand\t : TestLanguage.bool \215 TestLanguage.bool \8594 TestLanguage.bool\nand(\"True\", \"True\")\t = \"True\"\nand(_, _)\t = \"False\"\n\n\n\n TestLanguage.and (Rule) \n=========================\n\n\n \n---------------------------------------------- [ and ]\n (TestLanguage.\8594) (\"True\" \"&\" \"True\"), \"True\"\n\n\n"
-}
infoAbout'	:: LDScope -> [Name] -> [(FQName, AllInfo)]
infoAbout' langDefs names
	= let	fqn		= (init names, last names)
		search x	= resolve' langDefs x fqn & either (const Nothing)  (\(fqn, e) -> Just (fqn, getInfo e))
		in
		catMaybes [search syntaxCall, search functionCall, search relationCall, search ruleCall]




{- | Dumps all info about all entries in scope
>>> inScope testLanguage' |> fst |> fst |> showFQ & unlines
"TestLanguage.bool\nTestLanguage.expr\nTestLanguage.exprSum\nTestLanguage.int\nTestLanguage.op\nTestLanguage.tuple\nTestLanguage.and\nTestLanguage.nand\nTestLanguage.not\nTestLanguage.or\nTestLanguage.\8594\nTestLanguage.and\n"

-}	
inScope		:: LDScope -> [((FQName, [FQName]), AllInfo)]
inScope scope
	= let	ak x	= allKnowns scope x |> (\((fqn, _), names, x) -> ((fqn, names), getInfo x) )
		in	
		ak syntaxCall ++ ak functionCall ++ ak relationCall ++ ak ruleCall

{- | Gives the import flags for a scope
>>> infoImports testLanguage'
fromList [(["TestLanguage"],ImportFlags {_ifOrigin = "/TestLanguage.language", _ifIsSelf = True, _ifDiffName = [["TestLanguage"],[]]})]

-}
infoImports	:: LDScope -> Map [Name] ImportFlags
infoImports scope
	= scope & get (ldScope . imported)
		

resolveGlobal' lds entity fqn
	= resolveGlobal lds entity fqn |> snd



runFunction  	:: LangDefs -> FQName -> [ParseTree ()] -> Either String (ParseTree ())
runFunction	= resolveAndRun'


runExpression	:: LangDefs -> Expression SyntFormIndex -> Either String ParseTree'
runExpression lds expr
	= constructParseTree (const ()) lds empty expr

runExpression'	:: LangDefs -> FilePath -> FQName -> String -> Either String ParseTree'
runExpression' lds file expectedType input
	= do	expr	<- createTypedExpression lds file input expectedType
		let expr'	= expr |> snd
		runExpression lds expr'



{- | parseTarget: creates a parsetree based on the syntax of langdefs
>>> createParseTree testLanguage (["TestLanguage"], "exprSum") "?" "True & True" |>  toParsable
Right "True & True"
 -}
createParseTree		:: LangDefs -> FQName -> FilePath -> String -> Failable ParseTree'
createParseTree lds fq fp input
	= parseTarget lds fq fp input

{- | Creates an entire expression, which is untyped 
>>> createExpression testLanguage "?" "and(\"True\", \"True\")" |> toParsable
Right "and(\"True\", \"True\")"
-}
createExpression	:: LangDefs -> FilePath -> String -> Failable (Expression LocationInfo)
createExpression ld source str
	= do	pt	<- parse source (metaSyntaxes, ["Functions"]) "expression" str
		Combiner.interpret expression pt

{- | Creates an expression and types it 
>>> createTypedExpression testLanguage "?" "and(\"True\",\"True\")" (["TestLanguage"],"bool") |> toParsable
Right "TestLanguage.and(\"True\", \"True\")"

-}

createTypedExpression	:: LangDefs -> FilePath -> String -> FQName -> Either String (Expression (LocationInfo, SyntFormIndex))
createTypedExpression ld source str typ@(loc, nm)
	= do	expr	<- legacy $ createExpression ld source str
		scope	<- legacy $ checkExistsSugg' dots loc (get langdefs ld)
				("Module "++dots loc++ " not found")	-- TODO make failable
		typeExpression scope typ expr



createPredicate		:: LangDefs -> FilePath -> String -> Failable (Either (Conclusion LocationInfo) (Expression LocationInfo))

createPredicate ld source str
	= do	pt	<- parse source (metaSyntaxes, ["Relations"]) "predicate" str
		Combiner.interpret predicate pt


