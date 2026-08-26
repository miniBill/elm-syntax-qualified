module Elm.Syntax.Qualified.Monad exposing (Monad, andThen, combineMap, fail, map, map2, map3, onContext, onContextThen, run, scope, succeed)


type alias Monad context error a =
    context -> Result error ( context, a )


succeed : a -> Monad context error a
succeed v context =
    Ok ( context, v )


fail : error -> Monad context error a
fail e _ =
    Err e


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


map3 :
    (a -> b -> c -> d)
    -> Monad context error a
    -> Monad context error b
    -> Monad context error c
    -> Monad context error d
map3 f a b c =
    succeed f
        |> andMap a
        |> andMap b
        |> andMap c


andThen : (a -> Monad context error b) -> Monad context error a -> Monad context error b
andThen f v context =
    case v context of
        Err e ->
            Err e

        Ok ( newContext, w ) ->
            f w newContext


scope : Monad context error a -> Monad context error a
scope v context =
    case v context of
        Err e ->
            Err e

        Ok ( _, w ) ->
            Ok ( context, w )


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


run : context -> Monad context error a -> Result error ( context, a )
run context v =
    v context


onContext :
    (context -> context)
    -> Monad context error a
    -> Monad context error a
onContext f v context =
    v context |> Result.map (Tuple.mapFirst f)


onContextThen : (context -> Result error context) -> Monad context error a -> Monad context error a
onContextThen f v context =
    case v context of
        Err e ->
            Err e

        Ok ( newContext, w ) ->
            case f newContext of
                Err e ->
                    Err e

                Ok adjustedContext ->
                    Ok ( adjustedContext, w )
