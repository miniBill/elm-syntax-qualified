module Elm.Syntax.Qualified.Monad exposing (..)

import Dict exposing (Dict)
import Elm.Package
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Qualified.PackageDict exposing (PackageDict)
import Result.Extra


type alias Monad context error a =
    context -> Result error ( context, a )


succeed : a -> Monad context error a
succeed v context =
    Ok ( context, v )


map : (a -> b) -> Monad context error a -> Monad context error b
map f v context =
    case v context of
        Err e ->
            Err e

        Ok ( newContext, w ) ->
            Ok ( newContext, f w )


andMap : Monad context error a -> Monad context error (a -> b) -> Monad context error b
andMap am fm context =
    case fm context of
        Err e ->
            Err e

        Ok ( newContext, f ) ->
            case am newContext of
                Err e ->
                    Err e

                Ok ( finalContext, a ) ->
                    Ok ( finalContext, f a )


map2 :
    (a -> b -> c)
    -> Monad context error a
    -> Monad context error b
    -> Monad context error c
map2 f a b =
    succeed f
        |> andMap a
        |> andMap b


andThen : (a -> Monad context error b) -> Monad context error a -> Monad context error b
andThen f v context =
    case v context of
        Err e ->
            Err e

        Ok ( newContext, w ) ->
            f w newContext


combineMap : (a -> Monad context error b) -> List a -> Monad context error (List b)
combineMap f list context =
    combineMapHelp f list [] context


combineMapHelp :
    (a -> context -> Result error ( context, b ))
    -> List a
    -> List b
    -> context
    -> Result error ( context, List b )
combineMapHelp f list acc context =
    case list of
        [] ->
            Ok ( context, List.reverse acc )

        a :: rest ->
            case f a context of
                Err e ->
                    Err e

                Ok ( newContext, newValue ) ->
                    combineMapHelp f rest (newValue :: acc) newContext
