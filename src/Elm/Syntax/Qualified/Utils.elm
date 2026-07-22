module Elm.Syntax.Qualified.Utils exposing (authorProject)

import Elm.Package


{-| `author/project` package name, to use with applications.
-}
authorProject : Elm.Package.Name
authorProject =
    case Elm.Package.fromString "author/project" of
        Nothing ->
            crash ()

        Just name ->
            name


crash : () -> a
crash () =
    let
        _ =
            modBy 0 0
    in
    crash ()
