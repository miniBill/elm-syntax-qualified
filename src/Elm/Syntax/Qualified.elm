module Elm.Syntax.Qualified exposing (Declaration(..), EffectModuleData, Expression(..), File, ModuleType(..), PackageInterface, QualifyError(..), fromUnqualified)

import Dict exposing (Dict)
import Elm.Package
import Elm.Project
import Elm.Syntax.Declaration as Declaration
import Elm.Syntax.Documentation exposing (Documentation)
import Elm.Syntax.Exposing as Exposing exposing (Exposing)
import Elm.Syntax.Expression as Expression exposing (Expression, Function)
import Elm.Syntax.File
import Elm.Syntax.Import as Import
import Elm.Syntax.Infix as Infix exposing (Infix)
import Elm.Syntax.Module
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Pattern as Pattern exposing (Pattern)
import Elm.Syntax.Qualified.PackageDict exposing (PackageDict)
import Elm.Syntax.Range exposing (Range)
import Elm.Syntax.Signature as Signature exposing (Signature)
import Elm.Syntax.Type as Type exposing (Type, ValueConstructor)
import Elm.Syntax.TypeAlias as TypeAlias exposing (TypeAlias)


{-| Type annotation for a file
-}
type alias File =
    { moduleName : Node ModuleName
    , exposingList : Node Exposing.Exposing
    , moduleType : Node ModuleType
    , imports : List (Node Import)
    , declarations : List (Node Declaration)
    , comments : List (Node Comment)
    }


{-| Type alias representing an Import
-}
type alias Import =
    { packageName : Elm.Package.Name
    , moduleName : Node ModuleName
    , moduleAlias : Maybe (Node ModuleName)
    , exposingList : Maybe (Node Exposing.Exposing)
    }


{-| Type representing the comment syntax
-}
type alias Comment =
    String


{-| Custom type that represents all different top-level declarations.

These can be one of the following:

  - Functions: `add x y = x + y`
  - Custom types: `type Color = Blue | Red`
  - Type aliases: `type alias Status = Int`
  - Port declaration: `port sendMessage: String -> Cmd msg`
  - Infix declarations. You will probably not need this, while only core packages can define these.

-}
type Declaration
    = FunctionDeclaration Function
    | AliasDeclaration TypeAlias
    | CustomTypeDeclaration Type
    | PortDeclaration Signature
    | InfixDeclaration Infix


{-| Type alias that defines the syntax for a custom type.
All information that you can define in a type alias is embedded.
-}
type alias Type =
    { documentation : Maybe (Node Documentation)
    , name : Node String
    , generics : List (Node String)
    , constructors : List (Node ValueConstructor)
    }


{-| Custom type for all expressions such as:

  - `Unit`: `()`
  - `Application`: `add a b`
  - `OperatorApplication`: `a + b`
  - `FunctionOrValue`: `add` or `True`
  - `IfBlock`: `if a then b else c`
  - `PrefixOperator`: `(+)`
  - `Integer`: `42`
  - `Hex`: `0x1F`
  - `Floatable`: `42.0`
  - `Negation`: `-a`
  - `Literal`: `"text"`
  - `CharLiteral`: `'a'`
  - `TupledExpression`: `(a, b)` or `(a, b, c)`
  - `ParenthesizedExpression`: `(a)`
  - `LetExpression`: `let a = 4 in a`
  - `CaseExpression`: `case a of` followed by pattern matches
  - `LambdaExpression`: `(\a -> a)`
  - `RecordExpr`: `{ name = "text" }`
  - `ListExpr`: `[ x, y ]`
  - `RecordAccess`: `a.name`
  - `RecordAccessFunction`: `.name`
  - `RecordUpdateExpression`: `{ a | name = "text" }`
  - `GLSLExpression`: `[glsl| ... |]`

-}
type Expression
    = UnitExpression
    | ApplicationExpression (List (Node Expression))
    | OperatorApplicationExpression String (Node Expression) (Node Expression)
    | FunctionOrValueExpression Elm.Package.Name ModuleName String
    | IfBlockExpression (Node Expression) (Node Expression) (Node Expression)
    | PrefixOperatorExpression String
    | IntegerExpression Int
    | HexExpression Int
    | FloatExpression Float
    | NegationExpression (Node Expression)
    | StringExpression String
    | CharExpression Char
    | TupleExpression (Node Expression) (Node Expression)
    | TripleExpression (Node Expression) (Node Expression) (Node Expression)
    | ParenthesizedExpression (Node Expression)
    | LetExpression (List (Node LetDeclaration)) (Node Expression)
    | CaseExpression (Node Expression) (List Case)
    | LambdaExpression (List (Node Pattern)) (Node Expression)
    | RecordExpression (List (Node RecordSetter))
    | ListExpression (List (Node Expression))
    | RecordAccessExpression (Node Expression) (Node String)
    | RecordAccessFunctionExpression String
    | RecordUpdateExpression (Node String) (List (Node RecordSetter))
    | GLSLExpression String


{-| Expression for setting a record field
-}
type alias RecordSetter =
    ( Node String, Node Expression )


{-| A case in a case block
-}
type alias Case =
    ( Node Pattern, Node Expression )


{-| Union type for all possible declarations in a let block
-}
type LetDeclaration
    = LetFunction Function
    | LetDestructuring (Node Pattern) (Node Expression)


{-| Union type for different kind of modules
-}
type ModuleType
    = NormalModule
    | PortModule
    | EffectModule EffectModuleData


{-| Data for an effect module
-}
type alias EffectModuleData =
    { command : Maybe (Node String)
    , subscription : Maybe (Node String)
    }


{-| Exposed Type
-}
type alias ExposedType =
    { name : String
    , open : Maybe Range
    }


type Context
    = Context
        { packageName : Elm.Package.Name
        , dependencies : PackageDict PackageInterface
        , elmJson : Elm.Project.Project
        , modules : Dict ModuleName ResolvesTo
        }


type ResolvesTo
    = ResolvesToPackage Elm.Package.Name
    | IsAmbiguous


fromUnqualified :
    Context
    -> Elm.Syntax.File.File
    -> Result QualifyError File
fromUnqualified input file =
    let
        ( moduleName, exposingList, moduleType ) =
            case file.moduleDefinition of
                Node range (Elm.Syntax.Module.NormalModule normalModule) ->
                    ( normalModule.moduleName
                    , normalModule.exposingList
                    , Node range NormalModule
                    )

                Node range (Elm.Syntax.Module.PortModule portModule) ->
                    ( portModule.moduleName
                    , portModule.exposingList
                    , Node range PortModule
                    )

                Node range (Elm.Syntax.Module.EffectModule effectModule) ->
                    ( effectModule.moduleName
                    , effectModule.exposingList
                    , Node range (EffectModule { command = effectModule.command, subscription = effectModule.subscription })
                    )

        imports : List (Node Import)
        imports =
            List.map (qualifyImport input) file.imports

        r : File
        r =
            { moduleName = moduleName
            , exposingList = exposingList
            , moduleType = moduleType
            , imports = imports
            , declarations = List.map (qualifyDeclaration input imports) file.declarations
            , comments = file.comments
            }
    in
    Ok r


qualifyDeclaration :
    { packageName : Elm.Package.Name, dependencies : PackageDict PackageInterface, elmJson : Elm.Project.Project }
    -> List (Node Import)
    -> Node Declaration.Declaration
    -> Node Declaration
qualifyDeclaration arg1 arg2 arg3 =
    Debug.todo "TODO"


qualifyImport :
    { packageName : Elm.Package.Name, dependencies : PackageDict PackageInterface, elmJson : Elm.Project.Project }
    -> Node Import.Import
    -> Node Import
qualifyImport input import_ =
    { moduleName = import_.moduleName
    }


type QualifyError
    = MissingDependency Elm.Package.Name


type alias PackageInterface =
    Dict ModuleName ModuleInterface


type alias ModuleInterface =
    { exposingList : Exposing
    , types : Dict String Type
    , values : Dict String Function
    , aliases : Dict String TypeAlias
    , ports : Dict String Signature
    }
