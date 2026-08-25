module TestFiles exposing (run)

import BackendTask exposing (BackendTask)
import BackendTask.Do as Do
import BackendTask.Env as Env
import BackendTask.File as File
import Cli.Option
import Cli.OptionsParser exposing (OptionsParser)
import Cli.OptionsParser.BuilderState
import Cli.Program
import Elm.Project
import Elm.Syntax.Qualified
import FatalError exposing (FatalError)
import Json.Decode
import Pages.Internal.Platform.Cli as Cli
import Pages.Script as Script exposing (Script)


type alias CliOptions =
    { recurse : Bool
    , path : Maybe String
    }


run : Script
run =
    Script.withCliOptions config toTask


config : Cli.Program.Config CliOptions
config =
    Cli.Program.config
        |> Cli.Program.add optionsParser


optionsParser : OptionsParser CliOptions Cli.OptionsParser.BuilderState.NoBeginningOptions
optionsParser =
    Cli.OptionsParser.build CliOptions
        |> Cli.OptionsParser.with (Cli.Option.flag "recurse")
        |> Cli.OptionsParser.withOptionalPositionalArg (Cli.Option.optionalPositionalArg "path")


toTask : CliOptions -> BackendTask FatalError ()
toTask options =
    let
        pathTask : BackendTask FatalError String
        pathTask =
            case options.path of
                Just path ->
                    BackendTask.succeed path

                Nothing ->
                    Env.expect "HOME" |> BackendTask.allowFatal
    in
    Do.do pathTask <| \path ->
    (if options.recurse then
        Do.glob (path ++ "/**/elm.json")

     else
        Do.glob (path ++ "/elm.json")
    )
    <| \elmJsonList ->
    Do.each elmJsonList checkProject <| \_ ->
    Do.noop


checkProject : String -> BackendTask FatalError ()
checkProject elmJsonPath =
    Do.allowFatal (File.jsonFile Elm.Project.decoder elmJsonPath) <| \elmJson ->
    case elmJson of
        Elm.Project.Package _ ->
            Script.log ("[" ++ elmJsonPath ++ "] Found package - skipping")

        Elm.Project.Application application ->
            checkApplication elmJsonPath application


checkApplication : String -> Elm.Project.ApplicationInfo -> BackendTask FatalError ()
checkApplication elmJsonPath application =
    let
        projectPath =
            elmJsonPath |> String.split "/" |> List.reverse |> List.drop 1 |> List.reverse |> String.join "/"
    in
    BackendTask.fail (FatalError.fromString (elmJsonPath ++ " => " ++ projectPath))
