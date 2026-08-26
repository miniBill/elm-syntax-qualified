module Elm.Syntax.Qualified exposing
    ( File, Declaration(..), Case, Comment, CustomType, EffectModuleData, Expression(..), Function, FunctionImplementation, Import, LetDeclaration(..), ModuleInterface, ModuleType(..), PackageInterface, Pattern(..), QualifyError(..), RecordDefinition, RecordField, RecordSetter, Signature, Type(..), TypeAlias, ValueConstructor
    , PackageContext, initContext, addModule
    , fromUnqualified
    , toModuleInterface, unqualifiedToModuleInterface
    )

{-|

@docs File, Declaration, Case, Comment, CustomType, EffectModuleData, Expression, Function, FunctionImplementation, Import, LetDeclaration, ModuleInterface, ModuleType, PackageInterface, Pattern, QualifyError, RecordDefinition, RecordField, RecordSetter, Signature, Type, TypeAlias, ValueConstructor
@docs PackageContext, initContext, addModule
@docs fromUnqualified
@docs toModuleInterface, unqualifiedToModuleInterface

-}

import Dict exposing (Dict)
import Elm.Package
import Elm.Syntax.Declaration as Declaration
import Elm.Syntax.Documentation exposing (Documentation)
import Elm.Syntax.Exposing as Exposing exposing (Exposing)
import Elm.Syntax.Expression as Expression
import Elm.Syntax.File
import Elm.Syntax.Import as Import
import Elm.Syntax.Infix as Infix exposing (Infix)
import Elm.Syntax.Module as Module
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Pattern as Pattern
import Elm.Syntax.Qualified.Monad as Monad
import Elm.Syntax.Qualified.Utils as Utils
import Elm.Syntax.Range exposing (Range)
import Elm.Syntax.Signature as Signature
import Elm.Syntax.Type as Type
import Elm.Syntax.TypeAlias as TypeAlias
import Elm.Syntax.TypeAnnotation as TypeAnnotation exposing (TypeAnnotation)
import Maybe.Extra
import Result.Extra
import Set exposing (Set)


{-| Type annotation for a file
-}
type alias File =
    { moduleName : Node ModuleName
    , exposingList : Node Exposing
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
    , exposingList : Maybe (Node Exposing)
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
    | CustomTypeDeclaration CustomType
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
    , typeAnnotation : Node Type
    }


{-| Type alias that defines the syntax for a type alias.
A bit meta, but you get the idea. All information that you can define in a type alias is embedded.
-}
type alias TypeAlias =
    { documentation : Maybe (Node Documentation)
    , name : Node String
    , generics : List (Node String)
    , typeAnnotation : Node Type
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
type Type
    = GenericType String
    | NamedType (Node ( Elm.Package.Name, ModuleName, String )) (List (Node Type))
    | UnitType
    | TupleType (Node Type) (Node Type)
    | TripleType (Node Type) (Node Type) (Node Type)
    | RecordType RecordDefinition
    | GenericRecordType (Node String) (Node RecordDefinition)
    | FunctionType (Node Type) (Node Type)


{-| A list of fields in-order of a record type annotation.
-}
type alias RecordDefinition =
    List (Node RecordField)


{-| Single field of a record. A name and its type.
-}
type alias RecordField =
    ( Node String, Node Type )


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
type alias CustomType =
    { documentation : Maybe (Node Documentation)
    , name : Node String
    , generics : List (Node String)
    , constructors : List (Node ValueConstructor)
    }


{-| Syntax for a custom type value constructor.
-}
type alias ValueConstructor =
    { name : Node String
    , arguments : List (Node Type)
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


{-| Parsing context.
-}
type PackageContext
    = Context (ContextData ())


type alias ContextData moduleName =
    { packageName : Elm.Package.Name
    , moduleName : moduleName
    , availableModules : Dict ModuleName (ResolvesTo ModuleInterface)
    , visibleModules : Dict ModuleName (ResolvesTo ModuleName)
    , visibleTypes : Dict String (ResolvesTo ModuleName)
    , visibleValues : Dict String (ResolvesTo ModuleName)
    }


type ResolvesTo a
    = ResolvesToPackage Elm.Package.Name a
    | IsAmbiguous (List ( Elm.Package.Name, a ))


type alias Monad a =
    Monad.Monad (ContextData ModuleName) (Node QualifyError) a


type alias Monad_ a =
    Monad.Monad (ContextData ModuleName) QualifyError a


{-| Try building a fully-qualified `File` from an elm-syntax `File`.
-}
fromUnqualified :
    PackageContext
    -> Elm.Syntax.File.File
    -> Result ( Range, QualifyError ) File
fromUnqualified (Context packageContext) file =
    let
        ( moduleName, exposingList, moduleType ) =
            case file.moduleDefinition of
                Node range (Module.NormalModule normalModule) ->
                    ( normalModule.moduleName
                    , normalModule.exposingList
                    , Node range NormalModule
                    )

                Node range (Module.PortModule portModule) ->
                    ( portModule.moduleName
                    , portModule.exposingList
                    , Node range PortModule
                    )

                Node range (Module.EffectModule effectModule) ->
                    ( effectModule.moduleName
                    , effectModule.exposingList
                    , Node range (EffectModule { command = effectModule.command, subscription = effectModule.subscription })
                    )

        initialContext : ContextData ModuleName
        initialContext =
            { packageName = packageContext.packageName
            , moduleName = Node.value moduleName
            , availableModules = packageContext.availableModules
            , visibleModules = packageContext.visibleModules
            , visibleTypes = packageContext.visibleTypes
            , visibleValues = packageContext.visibleValues
            }

        result : Result (Node QualifyError) ( ContextData ModuleName, File )
        result =
            file.imports
                |> Monad.combineMap qualifyImport
                |> Monad.onContextThen
                    (\c ->
                        Result.Extra.foldlWhileOk
                            addDeclarationToContext
                            c
                            file.declarations
                    )
                |> Monad.andThen
                    (\imports ->
                        file.declarations
                            |> Monad.combineMap
                                (\decl ->
                                    decl
                                        |> qualifyDeclaration
                                        -- We already added the names to the initial context, avoid duplication
                                        |> Monad.scope
                                )
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
                |> Monad.run initialContext
    in
    case result of
        Ok ( _, v ) ->
            Ok v

        Err (Node range e) ->
            Err ( range, e )


addDeclarationToContext :
    Node Declaration.Declaration
    -> ContextData ModuleName
    -> Result (Node QualifyError) (ContextData ModuleName)
addDeclarationToContext (Node range decl) context =
    case decl of
        Declaration.InfixDeclaration _ ->
            Ok context

        Declaration.FunctionDeclaration function ->
            let
                (Node _ declaration) =
                    function.declaration

                here : ResolvesTo ModuleName
                here =
                    ResolvesToPackage context.packageName context.moduleName
            in
            { context
                | visibleValues = Dict.insert (Node.value declaration.name) here context.visibleValues
            }
                |> Ok

        Declaration.AliasDeclaration alias_ ->
            let
                (Node _ name) =
                    alias_.name

                here : ResolvesTo ModuleName
                here =
                    ResolvesToPackage context.packageName context.moduleName
            in
            case alias_.typeAnnotation of
                Node _ (TypeAnnotation.Record _) ->
                    { context
                        | visibleTypes = Dict.insert name here context.visibleTypes
                        , visibleValues = Dict.insert name here context.visibleValues
                    }
                        |> Ok

                _ ->
                    { context
                        | visibleTypes = Dict.insert name here context.visibleTypes
                    }
                        |> Ok

        Declaration.CustomTypeDeclaration custom ->
            let
                (Node _ name) =
                    custom.name

                here : ResolvesTo ModuleName
                here =
                    ResolvesToPackage context.packageName context.moduleName
            in
            List.foldl
                (\(Node _ constructor) acc ->
                    { acc
                        | visibleValues = Dict.insert (Node.value constructor.name) here acc.visibleValues
                    }
                )
                { context
                    | visibleTypes = Dict.insert name here context.visibleTypes
                }
                custom.constructors
                |> Ok

        Declaration.PortDeclaration { name } ->
            let
                here : ResolvesTo ModuleName
                here =
                    ResolvesToPackage context.packageName context.moduleName
            in
            { context
                | visibleValues = Dict.insert (Node.value name) here context.visibleValues
            }
                |> Ok

        Declaration.Destructuring _ _ ->
            Err (Node range InvalidSyntax)


qualifyDeclaration : Node Declaration.Declaration -> Monad (Node Declaration)
qualifyDeclaration (Node range declaration) =
    case declaration of
        Declaration.InfixDeclaration i ->
            Monad.succeed (Node range (InfixDeclaration i))

        Declaration.FunctionDeclaration f ->
            Monad.map (\q -> Node range (FunctionDeclaration q)) (qualifyFunctionDeclaration f)

        Declaration.AliasDeclaration a ->
            Monad.map (\q -> Node range (AliasDeclaration q)) (qualifyTypeAlias a)

        Declaration.CustomTypeDeclaration tipe ->
            Monad.map (\q -> Node range (CustomTypeDeclaration q)) (qualifyCustomType tipe)

        Declaration.PortDeclaration s ->
            Monad.map (\q -> Node range (PortDeclaration q)) (qualifySignature_ s)

        Declaration.Destructuring _ _ ->
            Monad.fail (Node range InvalidSyntax)


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
        (qualifyType alias_.typeAnnotation)


qualifyCustomType : Type.Type -> Monad CustomType
qualifyCustomType tipe =
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
        (Monad.combineMap qualifyType constructor.arguments)


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
        |> Monad.onContext (addLocalValueToContext (Node.value (Node.value f.declaration).name))


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
        (qualifyType signature.typeAnnotation)


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


qualifyType : Node TypeAnnotation -> Monad (Node Type)
qualifyType (Node range typeAnnotation) =
    case typeAnnotation of
        TypeAnnotation.Unit ->
            Monad.succeed (Node range UnitType)

        TypeAnnotation.GenericType v ->
            Monad.succeed (Node range (GenericType v))

        TypeAnnotation.Typed fullTypeName params ->
            Monad.map2 (\lc rc -> Node range (NamedType lc rc))
                (qualifyTypeName fullTypeName)
                (Monad.combineMap qualifyType params)

        TypeAnnotation.Tupled [ l, r ] ->
            Monad.map2
                (\ql qr ->
                    Node range (TupleType ql qr)
                )
                (qualifyType l)
                (qualifyType r)

        TypeAnnotation.Tupled [ l, m, r ] ->
            Monad.map3
                (\ql qm qr ->
                    Node range (TripleType ql qm qr)
                )
                (qualifyType l)
                (qualifyType m)
                (qualifyType r)

        TypeAnnotation.Tupled _ ->
            Monad.fail (Node range InvalidSyntax)

        TypeAnnotation.Record fields ->
            fields
                |> Monad.combineMap (qualifyNode qualifyRecordFieldAnnotation)
                |> Monad.map (\qf -> Node range (RecordType qf))

        TypeAnnotation.GenericRecord g (Node fieldsRange fields) ->
            fields
                |> Monad.combineMap (qualifyNode qualifyRecordFieldAnnotation)
                |> Monad.map (\qf -> Node range (GenericRecordType g (Node fieldsRange qf)))

        TypeAnnotation.FunctionTypeAnnotation from to ->
            Monad.map2
                (\f t ->
                    Node range (FunctionType f t)
                )
                (qualifyType from)
                (qualifyType to)


qualifyRecordFieldAnnotation : TypeAnnotation.RecordField -> Monad RecordField
qualifyRecordFieldAnnotation ( name, annotation ) =
    Monad.map (Tuple.pair name) (qualifyType annotation)


qualifyTypeName : Node ( ModuleName, String ) -> Monad (Node ( Elm.Package.Name, ModuleName, String ))
qualifyTypeName name =
    qualifyNode_ qualifyTypeName_ name


qualifyTypeName_ : ( ModuleName, String ) -> Monad_ ( Elm.Package.Name, ModuleName, String )
qualifyTypeName_ ( moduleName, name ) context =
    if List.isEmpty moduleName then
        case Dict.get name context.visibleTypes of
            Nothing ->
                Err (UnqualifiedNameNotFound name)

            Just (ResolvesToPackage packageName realModuleName) ->
                Ok ( context, ( packageName, realModuleName, name ) )

            Just (IsAmbiguous alts) ->
                Err (ValueIsAmbiguous name (List.map Tuple.first alts))

    else
        case Dict.get moduleName context.visibleModules of
            Nothing ->
                Err (ModuleNotFound moduleName)

            Just (ResolvesToPackage packageName fullModuleName) ->
                Ok ( context, ( packageName, fullModuleName, name ) )

            Just (IsAmbiguous alts) ->
                Err (ModuleNameIsAmbiguous moduleName (List.map Tuple.first alts))


qualifyValue : Node ( ModuleName, String ) -> Monad (Node ( Elm.Package.Name, ModuleName, String ))
qualifyValue name =
    qualifyNode_ qualifyValue_ name


qualifyValue_ : ( ModuleName, String ) -> Monad_ ( Elm.Package.Name, ModuleName, String )
qualifyValue_ ( moduleName, name ) context =
    if List.isEmpty moduleName then
        case Dict.get name context.visibleValues of
            Nothing ->
                Err (UnqualifiedNameNotFound name)

            Just (ResolvesToPackage packageName realModuleName) ->
                Ok ( context, ( packageName, realModuleName, name ) )

            Just (IsAmbiguous alts) ->
                Err (ModuleNameIsAmbiguous moduleName (List.map Tuple.first alts))

    else
        case Dict.get moduleName context.visibleModules of
            Nothing ->
                Err (ModuleNotFound moduleName)

            Just (ResolvesToPackage packageName fullModuleName) ->
                Ok ( context, ( packageName, fullModuleName, name ) )

            Just (IsAmbiguous alts) ->
                Err (ModuleNameIsAmbiguous moduleName (List.map Tuple.first alts))


qualifyFunctionImplementation : Expression.FunctionImplementation -> Monad FunctionImplementation
qualifyFunctionImplementation functionImplementation =
    Monad.combineMap qualifyPattern functionImplementation.arguments
        |> Monad.andThen
            (\arguments ->
                qualifyExpression functionImplementation.expression
                    |> Monad.map
                        (\expression ->
                            { name = functionImplementation.name
                            , arguments = arguments
                            , expression = expression
                            }
                        )
            )
        |> Monad.scope


qualifyPattern : Node Pattern.Pattern -> Monad (Node Pattern)
qualifyPattern (Node range pattern) =
    case pattern of
        Pattern.AllPattern ->
            Monad.succeed (Node range AllPattern)

        Pattern.UnitPattern ->
            Monad.succeed (Node range UnitPattern)

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

        Pattern.RecordPattern cs ->
            List.foldl
                (\(Node _ e) m ->
                    Monad.onContext (addLocalValueToContext e) m
                )
                (Monad.succeed (Node range (RecordPattern cs)))
                cs

        Pattern.UnConsPattern l r ->
            Monad.map2
                (\ql qr -> Node range (UnConsPattern ql qr))
                (qualifyPattern l)
                (qualifyPattern r)

        Pattern.ListPattern cs ->
            cs
                |> Monad.combineMap qualifyPattern
                |> Monad.map (\qc -> Node range (ListPattern qc))

        Pattern.VarPattern v ->
            Monad.succeed (Node range (VarPattern v))
                |> Monad.onContext (addLocalValueToContext v)

        Pattern.NamedPattern qualified patterns ->
            Monad.map2
                (\(Node _ ( package, fullModuleName, typeName )) qp ->
                    Node range (NamedPattern package fullModuleName typeName qp)
                )
                (qualifyValue (Node range ( qualified.moduleName, qualified.name )))
                (Monad.combineMap qualifyPattern patterns)

        Pattern.AsPattern c n ->
            qualifyPattern c
                |> Monad.map (\qc -> Node range (AsPattern qc n))
                |> Monad.onContext (addLocalValueToContext (Node.value n))

        Pattern.ParenthesizedPattern p ->
            Monad.map (\qp -> Node range (ParenthesizedPattern qp)) (qualifyPattern p)


addLocalValueToContext : String -> ContextData ModuleName -> ContextData ModuleName
addLocalValueToContext name context =
    { context
        | visibleValues =
            Dict.insert name (ResolvesToPackage context.packageName context.moduleName) context.visibleValues
    }


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

        Expression.IfBlock c t f ->
            Monad.map3
                (\cq tq fq -> Node range (IfBlockExpression cq tq fq))
                (qualifyExpression c)
                (qualifyExpression t)
                (qualifyExpression f)

        Expression.PrefixOperator p ->
            Monad.succeed (Node range (PrefixOperatorExpression p))

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
                |> addLetNamesToContext
                |> Monad.andThen
                    (\() ->
                        letBlock.declarations
                            |> Monad.combineMap
                                (\decl ->
                                    qualifyNode qualifyLetDeclaration decl
                                        -- We already added all the names above, we don't want duplicates
                                        |> Monad.scope
                                )
                            |> Monad.andThen
                                (\qualifiedDeclarations ->
                                    qualifyExpression letBlock.expression
                                        |> Monad.map
                                            (\qualifiedExpression ->
                                                Node range
                                                    (LetExpression qualifiedDeclarations qualifiedExpression)
                                            )
                                )
                    )
                |> Monad.scope

        Expression.CaseExpression caseExpression ->
            Monad.map2 (\qe qb -> Node range (CaseExpression qe qb))
                (qualifyExpression caseExpression.expression)
                (Monad.combineMap qualifyCase caseExpression.cases)

        Expression.LambdaExpression lambda ->
            qualifyLambdaExpression lambda
                |> Monad.map (\( qp, qe ) -> Node range (LambdaExpression qp qe))

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

        Expression.RecordAccessFunction n ->
            Monad.succeed (Node range (RecordAccessFunctionExpression n))

        Expression.RecordUpdateExpression n rs ->
            rs
                |> Monad.combineMap
                    (\(Node updaterRange ( k, v )) ->
                        Monad.map (\qv -> Node updaterRange ( k, qv )) (qualifyExpression v)
                    )
                |> Monad.map (\qrs -> Node range (RecordUpdateExpression n qrs))

        Expression.GLSLExpression t ->
            Monad.succeed (Node range (GLSLExpression t))


addLetNamesToContext : List (Node Expression.LetDeclaration) -> Monad ()
addLetNamesToContext declarations =
    Monad.combineMap addLetNameToContext declarations
        |> Monad.map (\_ -> ())


addLetNameToContext : Node Expression.LetDeclaration -> Monad ()
addLetNameToContext (Node _ declaration) =
    case declaration of
        Expression.LetDestructuring p _ ->
            qualifyPattern p
                |> Monad.map (\_ -> ())

        Expression.LetFunction function ->
            let
                (Node _ name) =
                    (Node.value function.declaration).name
            in
            Monad.succeed ()
                |> Monad.onContext (addLocalValueToContext name)


qualifyLambdaExpression : Expression.Lambda -> Monad ( List (Node Pattern), Node Expression )
qualifyLambdaExpression { args, expression } =
    args
        |> Monad.combineMap qualifyPattern
        |> Monad.andThen
            (\qps ->
                qualifyExpression expression
                    |> Monad.map (\e -> ( qps, e ))
            )
        |> Monad.scope


qualifyCase : Expression.Case -> Monad Case
qualifyCase ( pattern, expression ) =
    Monad.map2 Tuple.pair
        (qualifyPattern pattern)
        (qualifyExpression expression)
        |> Monad.scope


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
    case qualifyValue_ ( moduleName, name ) context of
        Ok ( newContext, ( packageName, qualifiedModuleName, _ ) ) ->
            Ok ( newContext, Node range (FunctionOrValueExpression packageName qualifiedModuleName name) )

        Err e ->
            Err (Node range e)


qualifyRecordField : Node Expression.RecordSetter -> Monad (Node RecordSetter)
qualifyRecordField (Node range ( field, expression )) =
    Monad.map (\qe -> Node range ( field, qe )) (qualifyExpression expression)


qualifyImport : Node Import.Import -> Monad (Node Import)
qualifyImport v =
    qualifyNode_ qualifyImport_ v


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
                exposedResult : Result QualifyError ( List String, List String )
                exposedResult =
                    case import_.exposingList of
                        Nothing ->
                            Ok ( [], [] )

                        Just (Node _ (Exposing.All _)) ->
                            Ok ( Dict.keys moduleInterface.types, Set.toList moduleInterface.values )

                        Just (Node _ (Exposing.Explicit list)) ->
                            list
                                |> Result.Extra.combineMap calculateExpose
                                |> Result.map
                                    (\l ->
                                        l
                                            |> List.unzip
                                            |> Tuple.mapBoth List.concat List.concat
                                    )

                calculateExpose : Node Exposing.TopLevelExpose -> Result QualifyError ( List String, List String )
                calculateExpose (Node _ expose) =
                    case expose of
                        Exposing.InfixExpose _ ->
                            Ok ( [], [] )

                        Exposing.FunctionExpose name ->
                            Ok ( [], [ name ] )

                        Exposing.TypeOrAliasExpose name ->
                            case Dict.get name moduleInterface.types of
                                Just variants ->
                                    Ok ( [ name ], variants )

                                Nothing ->
                                    Err (ValueNotFound imported name)

                        Exposing.TypeExpose { name, open } ->
                            case open of
                                Nothing ->
                                    Ok ( [ name ], [] )

                                Just _ ->
                                    case Dict.get name moduleInterface.types of
                                        Just variants ->
                                            Ok ( [ name ], variants )

                                        Nothing ->
                                            Err (ValueNotFound imported name)
            in
            exposedResult
                |> Result.map
                    (\( exposedTypes, exposedValues ) ->
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
                                    , visibleTypes =
                                        List.foldl
                                            (\e ->
                                                insertResolvesTo e
                                                    packageName
                                                    imported
                                            )
                                            context.visibleTypes
                                            exposedTypes
                                    , visibleValues =
                                        List.foldl
                                            (\e ->
                                                insertResolvesTo e
                                                    packageName
                                                    imported
                                            )
                                            context.visibleValues
                                            exposedValues
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

        Just (IsAmbiguous alts) ->
            Err (ModuleNameIsAmbiguous imported (List.map Tuple.first alts))

        Nothing ->
            Err (ModuleNotFound imported)


{-| -}
type QualifyError
    = ModuleNotFound ModuleName
    | ModuleNameIsAmbiguous ModuleName (List Elm.Package.Name)
    | ValueIsAmbiguous String (List Elm.Package.Name)
    | InvalidSyntax
    | ValueNotFound ModuleName String
    | UnqualifiedNameNotFound String


{-| A dictionary of all values and types a package exposes.
-}
type alias PackageInterface =
    Dict ModuleName ModuleInterface


{-| Values and types exposed by a module.
-}
type alias ModuleInterface =
    { types : Dict String (List String)
    , values : Set String
    }


{-| Build a `Context`.
-}
initContext : { packageName : Elm.Package.Name } -> PackageContext
initContext { packageName } =
    Context
        { packageName = packageName
        , moduleName = ()
        , availableModules = Dict.empty
        , visibleModules = defaultVisibleModules
        , visibleTypes = defaultVisibleTypes
        , visibleValues = defaultVisibleValues
        }


defaultVisibleValues : Dict String (ResolvesTo ModuleName)
defaultVisibleValues =
    [ ( "abs", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "acos", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "always", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "asin", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "atan", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "atan2", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "ceiling", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "clamp", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "compare", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "cos", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "degrees", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "e", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "EQ", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "False", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "floor", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "fromPolar", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "GT", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "identity", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "isInfinite", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "isNaN", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "logBase", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "LT", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "max", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "min", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "modBy", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "negate", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "never", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "not", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "pi", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "radians", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "remainderBy", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "round", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "sin", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "sqrt", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "tan", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "toFloat", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "toPolar", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "True", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "truncate", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "turns", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "xor", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "Just", ResolvesToPackage Utils.elmCore [ "Maybe" ] )
    , ( "Nothing", ResolvesToPackage Utils.elmCore [ "Maybe" ] )
    , ( "Ok", ResolvesToPackage Utils.elmCore [ "Result" ] )
    , ( "Err", ResolvesToPackage Utils.elmCore [ "Result" ] )
    ]
        |> Dict.fromList


defaultVisibleTypes : Dict String (ResolvesTo ModuleName)
defaultVisibleTypes =
    [ ( "Int", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "Float", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "Order", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "Bool", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "Never", ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( "List", ResolvesToPackage Utils.elmCore [ "List" ] )
    , ( "Maybe", ResolvesToPackage Utils.elmCore [ "Maybe" ] )
    , ( "Result", ResolvesToPackage Utils.elmCore [ "Result" ] )
    , ( "String", ResolvesToPackage Utils.elmCore [ "String" ] )
    , ( "Char", ResolvesToPackage Utils.elmCore [ "Char" ] )
    , ( "Program", ResolvesToPackage Utils.elmCore [ "Platform" ] )
    , ( "Cmd", ResolvesToPackage Utils.elmCore [ "Platform.Cmd" ] )
    , ( "Sub", ResolvesToPackage Utils.elmCore [ "Platform.Sub" ] )
    ]
        |> Dict.fromList


defaultVisibleModules : Dict ModuleName (ResolvesTo ModuleName)
defaultVisibleModules =
    [ ( [ "Basics" ], ResolvesToPackage Utils.elmCore [ "Basics" ] )
    , ( [ "List" ], ResolvesToPackage Utils.elmCore [ "List" ] )
    , ( [ "Maybe" ], ResolvesToPackage Utils.elmCore [ "Maybe" ] )
    , ( [ "Result" ], ResolvesToPackage Utils.elmCore [ "Result" ] )
    , ( [ "String" ], ResolvesToPackage Utils.elmCore [ "String" ] )
    , ( [ "Char" ], ResolvesToPackage Utils.elmCore [ "Char" ] )
    , ( [ "Tuple" ], ResolvesToPackage Utils.elmCore [ "Tuple" ] )
    , ( [ "Debug" ], ResolvesToPackage Utils.elmCore [ "Debug" ] )
    , ( [ "Platform" ], ResolvesToPackage Utils.elmCore [ "Platform" ] )
    , ( [ "Cmd" ], ResolvesToPackage Utils.elmCore [ "Platform", "Cmd" ] )
    , ( [ "Sub" ], ResolvesToPackage Utils.elmCore [ "Platform", "Sub" ] )
    ]
        |> Dict.fromList


addModule : Elm.Package.Name -> ModuleName -> ModuleInterface -> PackageContext -> PackageContext
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
                Just (ResolvesToPackage existingPackageName existingValue) ->
                    Just
                        (IsAmbiguous
                            [ ( packageName, value )
                            , ( existingPackageName, existingValue )
                            ]
                        )

                Nothing ->
                    Just (ResolvesToPackage packageName value)

                Just (IsAmbiguous alts) ->
                    Just (IsAmbiguous (( packageName, value ) :: alts))
        )
        dict


unqualifiedToModuleInterface : Elm.Syntax.File.File -> ModuleInterface
unqualifiedToModuleInterface file =
    let
        exposingList : Node Exposing
        exposingList =
            case file.moduleDefinition of
                Node _ (Module.NormalModule normal) ->
                    normal.exposingList

                Node _ (Module.PortModule portModule) ->
                    portModule.exposingList

                Node _ (Module.EffectModule effectModule) ->
                    effectModule.exposingList

        exposed : Maybe { exposedTypes : Dict String Bool, exposedValues : Set String }
        exposed =
            case exposingList of
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
                    -> List (Node Type.ValueConstructor)
                    -> ModuleInterface
                    -> ModuleInterface
                exposeType (Node _ name) constructors a =
                    { a
                        | types =
                            Dict.insert name
                                (List.map (\(Node _ c) -> Node.value c.name) constructors)
                                a.types
                    }

                exposeValue :
                    Node String
                    -> ModuleInterface
                    -> ModuleInterface
                exposeValue (Node _ name) a =
                    { a | values = Set.insert name a.values }

                exposeVariants :
                    List (Node Type.ValueConstructor)
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
                Declaration.InfixDeclaration _ ->
                    acc

                Declaration.CustomTypeDeclaration { name, constructors } ->
                    case exposed of
                        Nothing ->
                            acc
                                |> exposeType name constructors
                                |> exposeVariants constructors

                        Just { exposedTypes } ->
                            case Dict.get (Node.value name) exposedTypes of
                                Nothing ->
                                    acc

                                Just False ->
                                    acc |> exposeType name []

                                Just True ->
                                    acc
                                        |> exposeType name constructors
                                        |> exposeVariants constructors

                Declaration.FunctionDeclaration { declaration } ->
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

                Declaration.AliasDeclaration { name, typeAnnotation } ->
                    case typeAnnotation of
                        Node _ (TypeAnnotation.Record _) ->
                            case exposed of
                                Nothing ->
                                    acc
                                        |> exposeType name []
                                        |> exposeValue name

                                Just { exposedTypes } ->
                                    case Dict.get (Node.value name) exposedTypes of
                                        Nothing ->
                                            acc

                                        Just _ ->
                                            acc
                                                |> exposeType name []
                                                |> exposeValue name

                        _ ->
                            case exposed of
                                Nothing ->
                                    acc
                                        |> exposeType name []

                                Just { exposedTypes } ->
                                    case Dict.get (Node.value name) exposedTypes of
                                        Nothing ->
                                            acc

                                        Just _ ->
                                            acc
                                                |> exposeType name []

                Declaration.PortDeclaration { name } ->
                    case exposed of
                        Nothing ->
                            acc |> exposeValue name

                        Just { exposedValues } ->
                            if Set.member (Node.value name) exposedValues then
                                acc |> exposeValue name

                            else
                                acc

                Declaration.Destructuring _ _ ->
                    acc
        )
        { types = Dict.empty
        , values = Set.empty
        }
        file.declarations


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
                    -> List (Node ValueConstructor)
                    -> ModuleInterface
                    -> ModuleInterface
                exposeType (Node _ name) constructors a =
                    { a
                        | types =
                            Dict.insert name
                                (List.map (\(Node _ c) -> Node.value c.name) constructors)
                                a.types
                    }

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
                                |> exposeType name constructors
                                |> exposeVariants constructors

                        Just { exposedTypes } ->
                            case Dict.get (Node.value name) exposedTypes of
                                Nothing ->
                                    acc

                                Just False ->
                                    acc
                                        |> exposeType name []

                                Just True ->
                                    acc
                                        |> exposeType name constructors
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

                AliasDeclaration { name, typeAnnotation } ->
                    case typeAnnotation of
                        Node _ (RecordType _) ->
                            case exposed of
                                Nothing ->
                                    acc
                                        |> exposeType name []
                                        |> exposeValue name

                                Just { exposedTypes } ->
                                    case Dict.get (Node.value name) exposedTypes of
                                        Nothing ->
                                            acc

                                        Just _ ->
                                            acc
                                                |> exposeType name []
                                                |> exposeValue name

                        _ ->
                            case exposed of
                                Nothing ->
                                    acc
                                        |> exposeType name []

                                Just { exposedTypes } ->
                                    case Dict.get (Node.value name) exposedTypes of
                                        Nothing ->
                                            acc

                                        Just _ ->
                                            acc
                                                |> exposeType name []

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
        { types = Dict.empty
        , values = Set.empty
        }
        file.declarations
