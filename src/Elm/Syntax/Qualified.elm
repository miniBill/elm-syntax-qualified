module Elm.Syntax.Qualified exposing
    ( File, ModuleType(..), EffectModuleData, Import, Declaration(..), Expression(..)
    , fromUnqualified, QualifyError(..), Context, initContext, addModule
    )

{-|

@docs File, ModuleType, EffectModuleData, Import, Declaration, Expression

@docs fromUnqualified, QualifyError, Context, initContext, addModule

-}

import Dict exposing (Dict)
import Elm.Package
import Elm.Project
import Elm.Syntax.Declaration as Declaration
import Elm.Syntax.Documentation exposing (Documentation)
import Elm.Syntax.Exposing as Exposing exposing (Exposing)
import Elm.Syntax.Expression as Expression
import Elm.Syntax.File
import Elm.Syntax.Import as Import
import Elm.Syntax.Infix as Infix exposing (Infix)
import Elm.Syntax.Module
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Pattern as Pattern
import Elm.Syntax.Qualified.Monad as Monad
import Elm.Syntax.Qualified.PackageDict as PackageDict exposing (PackageDict)
import Elm.Syntax.Range exposing (Range)
import Elm.Syntax.Signature as Signature
import Elm.Syntax.Type as Type exposing (Type, ValueConstructor)
import Elm.Syntax.TypeAlias as TypeAlias exposing (TypeAlias)
import Elm.Syntax.TypeAnnotation as TypeAnnotation
import Result.Extra


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


{-| Type alias for a full function
-}
type alias Function =
    { documentation : Maybe (Node Documentation)
    , signature : Maybe (Node Signature)
    , declaration : Node FunctionImplementation
    }


{-| Type alias representing a signature in Elm.
-}
type alias Signature =
    { name : Node String
    , typeAnnotation : Node TypeAnnotation
    }


{-| Custom type for different type annotations. For example:

  - `GenericType`: `a`
  - `NamedType`: `Maybe (Int -> String)`
  - `UnitType`: `()`
  - `TupleType`: `(a, b)`
  - `TripleType`: `(a, b, c)`
  - `RecordType`: `{ name : String}`
  - `GenericRecordType`: `{ a | name : String}`
  - `FunctionType`: `Int -> String`

-}
type TypeAnnotation
    = GenericType String
    | NamedType (Node ( Elm.Package.Name, ModuleName, String )) (List (Node TypeAnnotation))
    | UnitType
    | TupleType (Node TypeAnnotation) (Node TypeAnnotation)
    | TripleType (Node TypeAnnotation) (Node TypeAnnotation) (Node TypeAnnotation)
    | RecordType RecordDefinition
    | GenericRecordType (Node String) (Node RecordDefinition)
    | FunctionType (Node TypeAnnotation) (Node TypeAnnotation)


{-| A list of fields in-order of a record type annotation.
-}
type alias RecordDefinition =
    List (Node RecordField)


{-| Single field of a record. A name and its type.
-}
type alias RecordField =
    ( Node String, Node TypeAnnotation )


{-| Type alias for a function's implementation
-}
type alias FunctionImplementation =
    { name : Node String
    , arguments : List (Node Pattern)
    , expression : Node Expression
    }


{-| Custom type for all patterns such as:

  - `AllPattern`: `_`
  - `UnitPattern`: `()`
  - `CharPattern`: `'c'`
  - `StringPattern`: `"hello"`
  - `IntPattern`: `42`
  - `HexPattern`: `0x11`
  - `FloatPattern`: `42.0`
  - `TuplePattern`: `(a, b)`
  - `RecordPattern`: `{name, age}`
  - `UnConsPattern`: `x :: xs`
  - `ListPattern`: `[ x, y ]`
  - `VarPattern`: `x`
  - `NamedPattern`: `Just _`
  - `AsPattern`: `_ as x`
  - `ParenthesizedPattern`: `( _ )`

-}
type Pattern
    = AllPattern
    | UnitPattern
    | CharPattern Char
    | StringPattern String
    | IntPattern Int
    | HexPattern Int
    | FloatPattern Float
    | TuplePattern (List (Node Pattern))
    | RecordPattern (List (Node String))
    | UnConsPattern (Node Pattern) (Node Pattern)
    | ListPattern (List (Node Pattern))
    | VarPattern String
    | NamedPattern Elm.Package.Name ModuleName String (List (Node Pattern))
    | AsPattern (Node Pattern) (Node String)
    | ParenthesizedPattern (Node Pattern)


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

  - `UnitExpression`: `()`
  - `ApplicationExpression`: `add a b`
  - `OperatorApplicationExpression`: `a + b`
  - `FunctionOrValueExpression`: `add` or `True`
  - `IfBlockExpression`: `if a then b else c`
  - `PrefixOperatorExpression`: `(+)`
  - `IntegerExpression`: `42`
  - `HexExpression`: `0x1F`
  - `FloatExpression`: `42.0`
  - `NegationExpression`: `-a`
  - `StringExpression`: `"text"`
  - `CharExpression`: `'a'`
  - `TupleExpression`: `(a, b)`
  - `TripleExpression`: `(a, b, c)`
  - `ParenthesizedExpression`: `(a)`
  - `LetExpression`: `let a = 4 in a`
  - `CaseExpression`: `case a of` followed by pattern matches
  - `LambdaExpression`: `(\a -> a)`
  - `RecordExpression`: `{ name = "text" }`
  - `ListExpression`: `[ x, y ]`
  - `RecordAccessExpression`: `a.name`
  - `RecordAccessFunctionExpression`: `.name`
  - `RecordUpdateExpression`: `{ a | name = "text" }`
  - `GLSLExpression`: `[glsl| ... |]`

-}
type Expression
    = UnitExpression
    | ApplicationExpression (List (Node Expression))
    | OperatorApplicationExpression String (Node Expression) (Node Expression)
    | FunctionOrValueExpression (Maybe ( Elm.Package.Name, ModuleName )) String
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


{-| Parsing context.
-}
type Context
    = Context
        { packageName : Elm.Package.Name
        , dependencies : PackageDict PackageInterface
        , availableModules : Dict ModuleName (ResolvesTo ModuleInterface)
        , visibleModules : Dict ModuleName (ResolvesTo ())
        , visibleTypes : Dict String (ResolvesTo ())
        , visibleValues : Dict String (ResolvesTo ())
        }


type ResolvesTo a
    = ResolvesToPackage Elm.Package.Name a
    | IsAmbiguous


type alias Monad a =
    Monad.Monad Context QualifyError a


{-| Try building a fully-qualified `File` from an elm-syntax `File`.
-}
fromUnqualified :
    Context
    -> Elm.Syntax.File.File
    -> Result QualifyError File
fromUnqualified initialContext file =
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

        importsResult : Monad (List (Node Import))
        importsResult =
            file.imports
                |> Monad.combineMap (qualifyNode qualifyImport)
    in
    importsResult
        |> Monad.andThen
            (\imports ->
                file.declarations
                    |> Monad.combineMap
                        (qualifyNode qualifyDeclaration)
                    |> Monad.map
                        (\declarations ->
                            { moduleName = moduleName
                            , exposingList = exposingList
                            , moduleType = moduleType
                            , imports = imports
                            , declarations = declarations
                            , comments = file.comments
                            }
                        )
            )
        |> (\f -> f initialContext)
        |> Result.map Tuple.second


qualifyDeclaration : Declaration.Declaration -> Monad Declaration
qualifyDeclaration declaration =
    case declaration of
        Declaration.InfixDeclaration i ->
            Monad.succeed (InfixDeclaration i)

        Declaration.FunctionDeclaration f ->
            Monad.map FunctionDeclaration (qualifyFunctionDeclaration f)

        Declaration.AliasDeclaration _ ->
            Debug.todo "branch 'AliasDeclaration _' not implemented"

        Declaration.CustomTypeDeclaration _ ->
            Debug.todo "branch 'CustomTypeDeclaration _' not implemented"

        Declaration.PortDeclaration _ ->
            Debug.todo "branch 'PortDeclaration _' not implemented"

        Declaration.Destructuring _ _ ->
            Debug.todo "branch 'Destructuring _ _' not implemented"


qualifyFunctionDeclaration : Expression.Function -> Monad Function
qualifyFunctionDeclaration f =
    Monad.map2
        (\signature declaration ->
            { documentation = f.documentation
            , signature = signature
            , declaration = declaration
            }
        )
        (case f.signature of
            Nothing ->
                Monad.succeed Nothing

            Just signature ->
                Monad.map Just (qualifyNode qualifySignature signature)
        )
        (qualifyNode qualifyFunctionImplementation f.declaration)


qualifySignature : Signature.Signature -> Monad Signature
qualifySignature signature =
    Monad.map
        (\typeAnnotation ->
            { name = signature.name
            , typeAnnotation = typeAnnotation
            }
        )
        (qualifyNode qualifyTypeAnnotation signature.typeAnnotation)


qualifyNode : (a -> Monad b) -> Node a -> Monad (Node b)
qualifyNode f (Node range v) =
    Monad.map (Node range) (f v)


qualifyTypeAnnotation : TypeAnnotation.TypeAnnotation -> Monad TypeAnnotation
qualifyTypeAnnotation typeAnnotation =
    case typeAnnotation of
        TypeAnnotation.Unit ->
            Monad.succeed UnitType

        TypeAnnotation.GenericType _ ->
            Debug.todo "qualifyTypeAnnotation: branch 'GenericType _' not implemented"

        TypeAnnotation.Typed fullTypeName params ->
            Monad.map2 NamedType
                (qualifyNode qualifyTypeName fullTypeName)
                (Monad.combineMap (qualifyNode qualifyTypeAnnotation) params)

        TypeAnnotation.Tupled _ ->
            Debug.todo "qualifyTypeAnnotation: branch 'Tupled _' not implemented"

        TypeAnnotation.Record _ ->
            Debug.todo "qualifyTypeAnnotation: branch 'Record _' not implemented"

        TypeAnnotation.GenericRecord _ _ ->
            Debug.todo "qualifyTypeAnnotation: branch 'GenericRecord _ _' not implemented"

        TypeAnnotation.FunctionTypeAnnotation _ _ ->
            Debug.todo "qualifyTypeAnnotation: branch 'FunctionTypeAnnotation _ _' not implemented"


qualifyTypeName : ( ModuleName, String ) -> Monad ( Elm.Package.Name, ModuleName, String )
qualifyTypeName ( moduleName, typeName ) =
    Debug.todo "qualifyTypeName"


qualifyFunctionImplementation : Expression.FunctionImplementation -> Monad FunctionImplementation
qualifyFunctionImplementation arg1 =
    Debug.todo "qualifyFunctionImplementation"


qualifyImport : Import.Import -> Monad Import
qualifyImport import_ (Context context) =
    let
        imported : ModuleName
        imported =
            Node.value import_.moduleName
    in
    case Dict.get imported context.availableModules of
        Just (ResolvesToPackage packageName moduleInterface) ->
            let
                newContext : Context
                newContext =
                    Context
                        { context
                            | visibleModules =
                                insertResolvesTo
                                    (import_.moduleAlias
                                        |> Maybe.withDefault import_.moduleName
                                        |> Node.value
                                    )
                                    packageName
                                    ()
                                    context.visibleModules
                        }

                qualifiedImport : Import
                qualifiedImport =
                    { packageName = packageName
                    , moduleName = import_.moduleName
                    , moduleAlias = import_.moduleAlias
                    , exposingList = import_.exposingList
                    }
            in
            Ok ( newContext, qualifiedImport )

        Just IsAmbiguous ->
            Err (ModuleNameIsAmbiguous imported)

        Nothing ->
            Err (ModuleNotFound imported)


{-| -}
type QualifyError
    = MissingDependency Elm.Package.Name
    | ModuleNotFound ModuleName
    | ModuleNameIsAmbiguous ModuleName


{-| A dictionary of all values and types a package exposes.
-}
type alias PackageInterface =
    Dict ModuleName ModuleInterface


{-| Values and types exposed by a module.
-}
type alias ModuleInterface =
    { exposingList : Exposing
    , types : Dict String Type
    , values : Dict String Function
    , aliases : Dict String TypeAlias
    , ports : Dict String Signature
    }


{-| Build a `Context`.
-}
initContext : { packageName : Elm.Package.Name, elmJson : Elm.Project.Project } -> Context
initContext { packageName, elmJson } =
    Context
        { packageName = packageName
        , dependencies = PackageDict.empty
        , availableModules = Dict.empty
        , visibleModules = Dict.empty
        , visibleTypes = Dict.empty
        , visibleValues = Dict.empty
        }


addModule : Elm.Package.Name -> ModuleName -> ModuleInterface -> Context -> Context
addModule packageName moduleName moduleInterface (Context context) =
    Context
        { context
            | availableModules =
                insertResolvesTo moduleName packageName moduleInterface context.availableModules
        }


insertResolvesTo :
    comparable
    -> Elm.Package.Name
    -> a
    -> Dict comparable (ResolvesTo a)
    -> Dict comparable (ResolvesTo a)
insertResolvesTo key packageName value dict =
    Dict.update key
        (\existing ->
            case existing of
                Just _ ->
                    Just IsAmbiguous

                Nothing ->
                    Just (ResolvesToPackage packageName value)
        )
        dict
