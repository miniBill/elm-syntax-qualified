module TestFiles exposing (run)

import Ansi.Color
import BackendTask exposing (BackendTask)
import BackendTask.Do as Do
import BackendTask.Env as Env
import BackendTask.File as File
import BackendTask.Glob as Glob
import Cli.Option
import Cli.OptionsParser exposing (OptionsParser)
import Cli.OptionsParser.BuilderState
import Cli.Program
import Dict
import Elm.Package
import Elm.Parser
import Elm.Project
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Qualified as Qualified
import Elm.Syntax.Qualified.Utils
import FatalError exposing (FatalError)
import Json.Decode
import Pages.Internal.Platform.Cli as Cli
import Pages.Script as Script exposing (Script)
import Parser
import Parser.Error
import Set


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
    BackendTask.doEach (List.map checkProject elmJsonList)


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
        projectPath : String
        projectPath =
            elmJsonPath
                |> String.split "/"
                |> List.reverse
                |> List.drop 1
                |> List.reverse
                |> String.join "/"

        sourceDirectories : List String
        sourceDirectories =
            application.dirs |> List.map (\dir -> projectPath ++ "/" ++ dir)
    in
    Do.each sourceDirectories (\dir -> Glob.fromString (dir ++ "/**/*.elm")) <| \filesLists ->
    filesLists
        |> List.concat
        |> checkModules Elm.Syntax.Qualified.Utils.authorProject
            (Qualified.initContext
                { packageName = Elm.Syntax.Qualified.Utils.authorProject
                , elmJson = Elm.Project.Application application
                }
            )


checkModules : Elm.Package.Name -> Qualified.Context -> List String -> BackendTask FatalError ()
checkModules packageName =
    let
        go addedAny delayed context queue =
            case queue of
                [] ->
                    if List.isEmpty delayed then
                        BackendTask.succeed ()

                    else if addedAny then
                        go False [] context delayed

                    else
                        BackendTask.fail (FatalError.fromString ("Circular import? Delayed " ++ String.join ", " delayed))

                head :: tail ->
                    Do.allowFatal (File.rawFile head) <| \fileString ->
                    Do.do
                        (Elm.Parser.parseToFile fileString
                            |> Result.mapError (parseErrorToFatalError fileString)
                            |> BackendTask.fromResult
                        )
                    <| \file ->
                    case Qualified.fromUnqualified context file of
                        Ok qualified ->
                            let
                                newContext : Qualified.Context
                                newContext =
                                    let
                                        _ =
                                            Debug.todo

                                        -- Qualified.addModule
                                        --     packageName
                                        --     (Node.value qualified.moduleName)
                                        --     (Qualified.toModuleInterface qualified)
                                    in
                                    context
                            in
                            go True delayed newContext tail

                        Err ( _, Qualified.ModuleNotFound _ ) ->
                            go addedAny (head :: delayed) context tail

                        Err ( _, Qualified.ModuleNameIsAmbiguous _ ) ->
                            Debug.todo "branch 'Err (Node _ (ModuleNameIsAmbiguous _))' not implemented"

                        Err ( _, Qualified.InvalidSyntax ) ->
                            Debug.todo "branch 'Err (Node _ InvalidSyntax)' not implemented"
    in
    go False []


parseErrorToFatalError : String -> List Parser.DeadEnd -> FatalError
parseErrorToFatalError src deadEnds =
    Parser.Error.renderError
        { text = identity
        , formatContext = Ansi.Color.fontColor Ansi.Color.cyan
        , formatCaret = Ansi.Color.fontColor Ansi.Color.red
        , newline = "\n"
        , linesOfExtraContext = 3
        }
        Parser.Error.forParser
        src
        deadEnds
        |> String.concat
        |> FatalError.fromString
