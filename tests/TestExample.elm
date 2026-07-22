module TestExample exposing (..)

import Elm.Package as Package
import Elm.Parser
import Elm.Project as Project exposing (Project)
import Elm.Syntax.File
import Elm.Syntax.Qualified
import Elm.Syntax.Qualified.PackageDict as PackageDict
import Elm.Syntax.Qualified.Utils as Utils
import Expect
import Json.Decode
import Test exposing (Test, test)


suite : Test
suite =
    test "fromUnqualified succeed on example file" <|
        \_ ->
            case
                ( Json.Decode.decodeString Project.decoder elmJson
                , Elm.Parser.parseToFile file
                )
            of
                ( Err decodeError, _ ) ->
                    -- These are test bugs, not library bugs, whatever
                    Expect.fail (Json.Decode.errorToString decodeError)

                ( _, Err parseError ) ->
                    -- These are test bugs, not library bugs, whatever
                    Expect.fail (Debug.toString parseError)

                ( Ok parsedElmJson, Ok parsedFile ) ->
                    parsedFile
                        |> Elm.Syntax.Qualified.fromUnqualified
                            { packageName = Utils.authorProject
                            , dependencies = PackageDict.empty
                            , elmJson = parsedElmJson
                            }
                        |> Expect.ok


file : String
file =
    """module TestExample exposing (..)

import Test exposing (Test, test)

suite : Test
suite =
    test "fromUnqualified succeed on example file"
"""


elmJson : String
elmJson =
    """
    {
        "type": "package",
        "name": "miniBill/elm-syntax-qualified",
        "summary": "Companion to stil4m/elm-syntax when you need fully qualified values",
        "license": "BSD-3-Clause",
        "version": "1.0.0",
        "elm-version": "0.19.0 <= v < 0.20.0",
        "exposed-modules": [
            "Elm.Syntax.Qualified"
        ],
        "dependencies": {
            "elm/core": "1.0.0 <= v < 2.0.0",
            "elm/project-metadata-utils": "1.0.2 <= v < 2.0.0",
            "miniBill/elm-fast-dict": "1.2.6 <= v < 2.0.0",
            "stil4m/elm-syntax": "7.3.9 <= v < 8.0.0"
        },
        "test-dependencies": {
            "elm-explorations/test": "2.0.0 <= v < 3.0.0"
        }
    }
    """
