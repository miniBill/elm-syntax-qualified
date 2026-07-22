module Elm.Syntax.Qualified.PackageDict exposing (PackageDict, empty, get, insert)

import Elm.Package
import Elm.Version
import FastDict as Dict exposing (Dict)


type PackageDict v
    = PackageDict (Dict String v)


empty : PackageDict v
empty =
    PackageDict Dict.empty


insert : Elm.Package.Name -> v -> PackageDict v -> PackageDict v
insert name v (PackageDict d) =
    PackageDict (Dict.insert (Elm.Package.toString name) v d)


get : Elm.Package.Name -> PackageDict v -> Maybe v
get name (PackageDict d) =
    Dict.get (Elm.Package.toString name) d
