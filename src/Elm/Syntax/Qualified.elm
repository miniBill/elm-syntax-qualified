module Elm.Syntax.Qualified exposing
    ( File, ModuleType(..), EffectModuleData, Import, Declaration(..), Expression(..)
    , fromUnqualified, QualifyError(..), Context, initContext, addModule
    , ModuleInterface, PackageInterface, toModuleInterface
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
import Elm.Syntax.Type as Type
import Elm.Syntax.TypeAlias as TypeAlias
import Elm.Syntax.TypeAnnotation as TypeAnnotation
import Maybe.Extra
import Result.Extra
import Set exposing (Set)


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


{-| Type alias that defines the syntax for a type alias.
A bit meta, but you get the idea. All information that you can define in a type alias is embedded.
-}
type alias TypeAlias =
    { documentation : Maybe (Node Documentation)
    , name : Node String
    , generics : List (Node String)
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
    | TuplePattern (Node Pattern) (Node Pattern)
    | TriplePattern (Node Pattern) (Node Pattern) (Node Pattern)
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


{-| Syntax for a custom type value constructor.
-}
type alias ValueConstructor =
    { name : Node String
    , arguments : List (Node TypeAnnotation)
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
    | OperatorApplicationExpression String Infix.InfixDirection (Node Expression) (Node Expression)
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


{-| Parsing context.
-}
type Context
    = Context (ContextData ())


type alias ContextData moduleName =
    { packageName : Elm.Package.Name
    , moduleName : moduleName
    , dependencies : PackageDict PackageInterface
    , availableModules : Dict ModuleName (ResolvesTo ModuleInterface)
    , visibleModules : Dict ModuleName (ResolvesTo ModuleName)
    , visibleNames : Dict String (ResolvesTo ModuleName)
    }


type ResolvesTo a
    = ResolvesToPackage Elm.Package.Name a
    | IsAmbiguous


type alias Monad a =
    Monad.Monad (ContextData ModuleName) (Node QualifyError) a


type alias Monad_ a =
    Monad.Monad (ContextData ModuleName) QualifyError a


{-| Try building a fully-qualified `File` from an elm-syntax `File`.
-}
fromUnqualified :
    Context
    -> Elm.Syntax.File.File
    -> Result ( Range, QualifyError ) File
fromUnqualified (Context initialContext) file =
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

        result : Result (Node QualifyError) ( ContextData ModuleName, File )
        result =
            file.imports
                |> Monad.combineMap qualifyImport
                |> Monad.andThen
                    (\imports ->
                        file.declarations
                            |> Monad.combineMap qualifyDeclaration
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
                |> Monad.run
                    { packageName = initialContext.packageName
                    , moduleName = Node.value moduleName
                    , dependencies = initialContext.dependencies
                    , availableModules = initialContext.availableModules
                    , visibleModules = initialContext.visibleModules
                    , visibleNames = initialContext.visibleNames
                    }
    in
    case result of
        Ok ( _, v ) ->
            Ok v

        Err (Node range e) ->
            Err ( range, e )


qualifyDeclaration : Node Declaration.Declaration -> Monad (Node Declaration)
qualifyDeclaration v =
    qualifyNode qualifyDeclaration_ v


qualifyImport : Node Import.Import -> Monad (Node Import)
qualifyImport v =
    qualifyNode_ qualifyImport_ v


qualifyDeclaration_ : Declaration.Declaration -> Monad Declaration
qualifyDeclaration_ declaration =
    case declaration of
        Declaration.InfixDeclaration i ->
            Monad.succeed (InfixDeclaration i)

        Declaration.FunctionDeclaration f ->
            Monad.map FunctionDeclaration (qualifyFunctionDeclaration f)

        Declaration.AliasDeclaration a ->
            Monad.map AliasDeclaration (qualifyTypeAlias a)

        Declaration.CustomTypeDeclaration tipe ->
            Monad.map CustomTypeDeclaration (qualifyType tipe)

        Declaration.PortDeclaration _ ->
            Debug.todo "branch 'PortDeclaration _' not implemented"

        Declaration.Destructuring _ _ ->
            Debug.todo "branch 'Destructuring _ _' not implemented"


qualifyTypeAlias : TypeAlias.TypeAlias -> Monad TypeAlias
qualifyTypeAlias alias_ =
    Monad.map
        (\typeAnnotation ->
            { documentation = alias_.documentation
            , generics = alias_.generics
            , name = alias_.name
            , typeAnnotation = typeAnnotation
            }
        )
        (qualifyTypeAnnotation alias_.typeAnnotation)


qualifyType : Type.Type -> Monad Type
qualifyType tipe =
    Monad.map
        (\constructors ->
            { documentation = tipe.documentation
            , name = tipe.name
            , generics = tipe.generics
            , constructors = constructors
            }
        )
        (Monad.combineMap qualifyConstructor tipe.constructors)


qualifyConstructor : Node Type.ValueConstructor -> Monad (Node ValueConstructor)
qualifyConstructor v =
    qualifyNode qualifyConstructor_ v


qualifyConstructor_ : Type.ValueConstructor -> Monad ValueConstructor
qualifyConstructor_ constructor =
    Monad.map
        (\arguments ->
            { name = constructor.name, arguments = arguments }
        )
        (Monad.combineMap qualifyTypeAnnotation constructor.arguments)


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
                Monad.map Just (qualifySignature signature)
        )
        (qualifyNode qualifyFunctionImplementation f.declaration)


qualifySignature : Node Signature.Signature -> Monad (Node Signature)
qualifySignature s =
    qualifyNode qualifySignature_ s


qualifySignature_ : Signature.Signature -> Monad Signature
qualifySignature_ signature =
    Monad.map
        (\typeAnnotation ->
            { name = signature.name
            , typeAnnotation = typeAnnotation
            }
        )
        (qualifyTypeAnnotation signature.typeAnnotation)


qualifyNode : (a -> Monad b) -> Node a -> Monad (Node b)
qualifyNode f (Node range v) context =
    case f v context of
        Ok ( newContext, w ) ->
            Ok ( newContext, Node range w )

        Err e ->
            Err e


qualifyNode_ : (a -> Monad_ b) -> Node a -> Monad (Node b)
qualifyNode_ f (Node range v) context =
    case f v context of
        Ok ( newContext, w ) ->
            Ok ( newContext, Node range w )

        Err e ->
            Err (Node range e)


qualifyTypeAnnotation : Node TypeAnnotation.TypeAnnotation -> Monad (Node TypeAnnotation)
qualifyTypeAnnotation (Node range typeAnnotation) =
    case typeAnnotation of
        TypeAnnotation.Unit ->
            Monad.succeed (Node range UnitType)

        TypeAnnotation.GenericType v ->
            Monad.succeed (Node range (GenericType v))

        TypeAnnotation.Typed fullTypeName params ->
            Monad.map2 (\lc rc -> Node range (NamedType lc rc))
                (qualifyName fullTypeName)
                (Monad.combineMap qualifyTypeAnnotation params)

        TypeAnnotation.Tupled [ l, r ] ->
            Monad.map2
                (\ql qr ->
                    Node range (TupleType ql qr)
                )
                (qualifyTypeAnnotation l)
                (qualifyTypeAnnotation r)

        TypeAnnotation.Tupled [ l, m, r ] ->
            Monad.map3
                (\ql qm qr ->
                    Node range (TripleType ql qm qr)
                )
                (qualifyTypeAnnotation l)
                (qualifyTypeAnnotation m)
                (qualifyTypeAnnotation r)

        TypeAnnotation.Tupled _ ->
            Monad.fail (Node range InvalidSyntax)

        TypeAnnotation.Record fields ->
            fields
                |> Monad.combineMap (qualifyNode qualifyRecordFieldAnnotation)
                |> Monad.map (\qf -> Node range (RecordType qf))

        TypeAnnotation.GenericRecord _ _ ->
            Debug.todo "qualifyTypeAnnotation: branch 'GenericRecord _ _' not implemented"

        TypeAnnotation.FunctionTypeAnnotation from to ->
            Monad.map2
                (\f t ->
                    Node range (FunctionType f t)
                )
                (qualifyTypeAnnotation from)
                (qualifyTypeAnnotation to)


qualifyRecordFieldAnnotation : TypeAnnotation.RecordField -> Monad RecordField
qualifyRecordFieldAnnotation ( name, annotation ) =
    Monad.map (Tuple.pair name) (qualifyTypeAnnotation annotation)


qualifyName : Node ( ModuleName, String ) -> Monad (Node ( Elm.Package.Name, ModuleName, String ))
qualifyName name =
    qualifyNode_ qualifyName_ name


qualifyName_ : ( ModuleName, String ) -> Monad_ ( Elm.Package.Name, ModuleName, String )
qualifyName_ ( moduleName, name ) context =
    if List.isEmpty moduleName then
        case Dict.get name context.visibleNames of
            Nothing ->
                -- Must be a local type
                Ok ( context, ( context.packageName, context.moduleName, name ) )

            Just (ResolvesToPackage packageName realModuleName) ->
                Ok ( context, ( packageName, realModuleName, name ) )

            Just IsAmbiguous ->
                -- Should not happen for empty module names
                Err (ModuleNameIsAmbiguous moduleName)

    else
        case Dict.get moduleName context.availableModules of
            Nothing ->
                Err (ModuleNotFound moduleName)

            Just _ ->
                Debug.todo "branch 'Just _' not implemented"


qualifyFunctionImplementation : Expression.FunctionImplementation -> Monad FunctionImplementation
qualifyFunctionImplementation functionImplementation =
    Monad.map2
        (\arguments expression ->
            { name = functionImplementation.name
            , arguments = arguments
            , expression = expression
            }
        )
        (Monad.combineMap qualifyPattern functionImplementation.arguments)
        (qualifyExpression functionImplementation.expression)


qualifyPattern : Node Pattern.Pattern -> Monad (Node Pattern)
qualifyPattern (Node range pattern) =
    case pattern of
        Pattern.AllPattern ->
            Monad.succeed (Node range AllPattern)

        Pattern.UnitPattern ->
            Debug.todo "branch 'UnitPattern' not implemented"

        Pattern.CharPattern v ->
            Monad.succeed (Node range (CharPattern v))

        Pattern.StringPattern v ->
            Monad.succeed (Node range (StringPattern v))

        Pattern.IntPattern v ->
            Monad.succeed (Node range (IntPattern v))

        Pattern.HexPattern v ->
            Monad.succeed (Node range (HexPattern v))

        Pattern.FloatPattern v ->
            Monad.succeed (Node range (FloatPattern v))

        Pattern.TuplePattern [ l, r ] ->
            Monad.map2
                (\ql qr -> Node range (TuplePattern ql qr))
                (qualifyPattern l)
                (qualifyPattern r)

        Pattern.TuplePattern [ l, m, r ] ->
            Monad.map3
                (\ql qm qr -> Node range (TriplePattern ql qm qr))
                (qualifyPattern l)
                (qualifyPattern m)
                (qualifyPattern r)

        Pattern.TuplePattern _ ->
            Monad.fail (Node range InvalidSyntax)

        Pattern.RecordPattern _ ->
            Debug.todo "branch 'RecordPattern _' not implemented"

        Pattern.UnConsPattern _ _ ->
            Debug.todo "branch 'UnConsPattern _ _' not implemented"

        Pattern.ListPattern _ ->
            Debug.todo "branch 'ListPattern _' not implemented"

        Pattern.VarPattern v ->
            Monad.succeed (Node range (VarPattern v))

        Pattern.NamedPattern qualified patterns ->
            Monad.map2
                (\(Node _ ( package, fullModuleName, typeName )) qp ->
                    Node range (NamedPattern package fullModuleName typeName qp)
                )
                (qualifyName (Node range ( qualified.moduleName, qualified.name )))
                (Monad.combineMap qualifyPattern patterns)

        Pattern.AsPattern _ _ ->
            Debug.todo "branch 'AsPattern _ _' not implemented"

        Pattern.ParenthesizedPattern p ->
            Monad.map (\qp -> Node range (ParenthesizedPattern qp)) (qualifyPattern p)


qualifyExpression : Node Expression.Expression -> Monad (Node Expression)
qualifyExpression (Node range expression) =
    case expression of
        Expression.UnitExpr ->
            Monad.succeed (Node range UnitExpression)

        Expression.Application children ->
            children
                |> Monad.combineMap qualifyExpression
                |> Monad.map (\newChildren -> Node range (ApplicationExpression newChildren))

        Expression.OperatorApplication name direction l r ->
            Monad.map2
                (\lq rq ->
                    Node range (OperatorApplicationExpression name direction lq rq)
                )
                (qualifyExpression l)
                (qualifyExpression r)

        Expression.FunctionOrValue moduleName name ->
            qualifyFunctionOrValue range moduleName name

        Expression.IfBlock _ _ _ ->
            Debug.todo "qualifyExpression - branch 'IfBlock _ _ _' not implemented"

        Expression.PrefixOperator _ ->
            Debug.todo "qualifyExpression - branch 'PrefixOperator _' not implemented"

        Expression.Operator _ ->
            Monad.fail (Node range InvalidSyntax)

        Expression.Integer v ->
            Monad.succeed (Node range (IntegerExpression v))

        Expression.Hex v ->
            Monad.succeed (Node range (HexExpression v))

        Expression.Floatable v ->
            Monad.succeed (Node range (FloatExpression v))

        Expression.Negation e ->
            qualifyExpression e
                |> Monad.map (\c -> Node range (NegationExpression c))

        Expression.Literal v ->
            Monad.succeed (Node range (StringExpression v))

        Expression.CharLiteral v ->
            Monad.succeed (Node range (CharExpression v))

        Expression.TupledExpression [ l, r ] ->
            Monad.map2
                (\ql qr ->
                    Node range (TupleExpression ql qr)
                )
                (qualifyExpression l)
                (qualifyExpression r)

        Expression.TupledExpression [ l, m, r ] ->
            Monad.map3
                (\ql qm qr ->
                    Node range (TripleExpression ql qm qr)
                )
                (qualifyExpression l)
                (qualifyExpression m)
                (qualifyExpression r)

        Expression.TupledExpression _ ->
            Monad.fail (Node range InvalidSyntax)

        Expression.ParenthesizedExpression p ->
            Monad.map
                (\qp -> Node range (ParenthesizedExpression qp))
                (qualifyExpression p)

        Expression.LetExpression letBlock ->
            letBlock.declarations
                |> Monad.combineMap (qualifyNode qualifyLetDeclaration)
                |> Monad.andThen
                    (\qualifiedDeclarations ->
                        qualifyExpression letBlock.expression
                            |> Monad.map
                                (\qualifiedExpression ->
                                    Node range
                                        (LetExpression qualifiedDeclarations qualifiedExpression)
                                )
                    )

        Expression.CaseExpression caseExpression ->
            Monad.map2 (\qe qb -> Node range (CaseExpression qe qb))
                (qualifyExpression caseExpression.expression)
                (Monad.combineMap qualifyCase caseExpression.cases)

        Expression.LambdaExpression _ ->
            Debug.todo "qualifyExpression - branch 'LambdaExpression _' not implemented"

        Expression.RecordExpr fields ->
            fields
                |> Monad.combineMap qualifyRecordField
                |> Monad.map (\q -> Node range (RecordExpression q))

        Expression.ListExpr cs ->
            cs
                |> Monad.combineMap qualifyExpression
                |> Monad.map (\qc -> Node range (ListExpression qc))

        Expression.RecordAccess c name ->
            Monad.map
                (\qc -> Node range (RecordAccessExpression qc name))
                (qualifyExpression c)

        Expression.RecordAccessFunction _ ->
            Debug.todo "qualifyExpression - branch 'RecordAccessFunction _' not implemented"

        Expression.RecordUpdateExpression _ _ ->
            Debug.todo "qualifyExpression - branch 'RecordUpdateExpression _ _' not implemented"

        Expression.GLSLExpression _ ->
            Debug.todo "qualifyExpression - branch 'GLSLExpression _' not implemented"


qualifyCase : Expression.Case -> Monad Case
qualifyCase ( pattern, expression ) =
    Monad.map2 Tuple.pair
        (qualifyPattern pattern)
        (qualifyExpression expression)


qualifyLetDeclaration : Expression.LetDeclaration -> Monad LetDeclaration
qualifyLetDeclaration declaration =
    case declaration of
        Expression.LetDestructuring p e ->
            Monad.map2 LetDestructuring
                (qualifyPattern p)
                (qualifyExpression e)

        Expression.LetFunction function ->
            Monad.map LetFunction (qualifyFunctionDeclaration function)


qualifyFunctionOrValue : Range -> ModuleName -> String -> Monad (Node Expression)
qualifyFunctionOrValue range moduleName name context =
    case qualifyName_ ( moduleName, name ) context of
        Ok ( newContext, ( packageName, qualifiedModuleName, _ ) ) ->
            Ok ( newContext, Node range (FunctionOrValueExpression packageName qualifiedModuleName name) )

        Err e ->
            Err (Node range e)


qualifyRecordField : Node Expression.RecordSetter -> Monad (Node RecordSetter)
qualifyRecordField (Node range ( field, expression )) =
    Monad.map (\qe -> Node range ( field, qe )) (qualifyExpression expression)


qualifyImport_ : Import.Import -> Monad_ Import
qualifyImport_ import_ context =
    let
        imported : ModuleName
        imported =
            Node.value import_.moduleName
    in
    case Dict.get imported context.availableModules of
        Just (ResolvesToPackage packageName moduleInterface) ->
            let
                exposedResult : Result QualifyError (List String)
                exposedResult =
                    case import_.exposingList of
                        Nothing ->
                            Ok []

                        Just (Node _ (Exposing.All _)) ->
                            case Dict.get imported context.availableModules of
                                Nothing ->
                                    Err (ModuleNotFound imported)

                                Just _ ->
                                    Debug.todo "qualifyImport - branch 'Just _' not implemented"

                        Just (Node _ (Exposing.Explicit list)) ->
                            list
                                |> Result.Extra.combineMap calculateExpose
                                |> Result.map List.concat

                calculateExpose : Node Exposing.TopLevelExpose -> Result QualifyError (List String)
                calculateExpose (Node _ expose) =
                    case expose of
                        Exposing.InfixExpose _ ->
                            Ok []

                        Exposing.FunctionExpose name ->
                            Ok [ name ]

                        Exposing.TypeOrAliasExpose name ->
                            Ok [ name ]

                        Exposing.TypeExpose _ ->
                            Debug.todo "qualifyImport - branch TypeExpose"
            in
            exposedResult
                |> Result.map
                    (\exposed ->
                        let
                            newContext : ContextData ModuleName
                            newContext =
                                { context
                                    | visibleModules =
                                        insertResolvesTo
                                            (import_.moduleAlias
                                                |> Maybe.withDefault import_.moduleName
                                                |> Node.value
                                            )
                                            packageName
                                            imported
                                            context.visibleModules
                                    , visibleNames =
                                        List.foldl
                                            (\e ->
                                                insertResolvesTo e
                                                    packageName
                                                    imported
                                            )
                                            context.visibleNames
                                            exposed
                                }

                            qualifiedImport : Import
                            qualifiedImport =
                                { packageName = packageName
                                , moduleName = import_.moduleName
                                , moduleAlias = import_.moduleAlias
                                , exposingList = import_.exposingList
                                }
                        in
                        ( newContext, qualifiedImport )
                    )

        Just IsAmbiguous ->
            Err (ModuleNameIsAmbiguous imported)

        Nothing ->
            Err (ModuleNotFound imported)


{-| -}
type QualifyError
    = ModuleNotFound ModuleName
    | ModuleNameIsAmbiguous ModuleName
    | InvalidSyntax


{-| A dictionary of all values and types a package exposes.
-}
type alias PackageInterface =
    Dict ModuleName ModuleInterface


{-| Values and types exposed by a module.
-}
type alias ModuleInterface =
    { types : Set String
    , values : Set String
    }


{-| Build a `Context`.
-}
initContext : { packageName : Elm.Package.Name, elmJson : Elm.Project.Project } -> Context
initContext { packageName, elmJson } =
    Context
        { packageName = packageName
        , moduleName = ()
        , dependencies = PackageDict.empty
        , availableModules = Dict.empty
        , visibleModules = Dict.empty
        , visibleNames = Dict.empty
        }


addModule : Elm.Package.Name -> ModuleName -> ModuleInterface -> Context -> Context
addModule packageName moduleName moduleInterface (Context context) =
    Context
        { context
            | availableModules =
                insertResolvesTo moduleName packageName moduleInterface context.availableModules
        }


addPackage : Elm.Package.Name -> PackageInterface -> Context -> Context
addPackage packageName modules context =
    Dict.foldl (addModule packageName) context modules


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


type Exposed
    = NotExposed
    | ExposedOpaque
    | ExposedWithVariants


{-| -}
toModuleInterface : File -> ModuleInterface
toModuleInterface file =
    let
        exposed : Maybe { exposedTypes : Dict String Bool, exposedValues : Set String }
        exposed =
            case file.exposingList of
                Node _ (Exposing.All _) ->
                    Nothing

                Node _ (Exposing.Explicit list) ->
                    List.foldl
                        (\(Node _ e) a ->
                            case e of
                                Exposing.TypeExpose { name, open } ->
                                    { a
                                        | exposedTypes =
                                            Dict.insert name (Maybe.Extra.isJust open) a.exposedTypes
                                    }

                                Exposing.InfixExpose _ ->
                                    a

                                Exposing.FunctionExpose f ->
                                    { a
                                        | exposedValues = Set.insert f a.exposedValues
                                    }

                                Exposing.TypeOrAliasExpose name ->
                                    { a
                                        | exposedTypes =
                                            Dict.insert name False a.exposedTypes
                                    }
                        )
                        { exposedTypes = Dict.empty
                        , exposedValues = Set.empty
                        }
                        list
                        |> Just
    in
    List.foldl
        (\(Node _ decl) acc ->
            let
                exposeType :
                    Node String
                    -> ModuleInterface
                    -> ModuleInterface
                exposeType (Node _ name) a =
                    { a | types = Set.insert name a.types }

                exposeValue :
                    Node String
                    -> ModuleInterface
                    -> ModuleInterface
                exposeValue (Node _ name) a =
                    { a | values = Set.insert name a.values }

                exposeVariants :
                    List (Node ValueConstructor)
                    -> ModuleInterface
                    -> ModuleInterface
                exposeVariants constructors a =
                    { a
                        | values =
                            List.foldl
                                (\(Node _ e) -> Set.insert (Node.value e.name))
                                a.values
                                constructors
                    }
            in
            case decl of
                InfixDeclaration _ ->
                    acc

                CustomTypeDeclaration { name, constructors } ->
                    case exposed of
                        Nothing ->
                            acc
                                |> exposeType name
                                |> exposeVariants constructors

                        Just { exposedTypes } ->
                            case Dict.get (Node.value name) exposedTypes of
                                Nothing ->
                                    acc

                                Just False ->
                                    acc |> exposeType name

                                Just True ->
                                    acc
                                        |> exposeType name
                                        |> exposeVariants constructors

                FunctionDeclaration { declaration } ->
                    let
                        name : Node String
                        name =
                            (Node.value declaration).name
                    in
                    case exposed of
                        Nothing ->
                            acc |> exposeValue name

                        Just { exposedValues } ->
                            if Set.member (Node.value name) exposedValues then
                                acc |> exposeValue name

                            else
                                acc

                AliasDeclaration _ ->
                    Debug.todo "branch 'AliasDeclaration _' not implemented"

                PortDeclaration { name } ->
                    case exposed of
                        Nothing ->
                            acc |> exposeValue name

                        Just { exposedValues } ->
                            if Set.member (Node.value name) exposedValues then
                                acc |> exposeValue name

                            else
                                acc
        )
        { types = Set.empty
        , values = Set.empty
        }
        file.declarations
