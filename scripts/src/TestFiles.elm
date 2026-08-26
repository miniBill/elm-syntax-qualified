module TestFiles exposing (run)

import Ansi.Color
import BackendTask exposing (BackendTask)
import BackendTask.Do as Do
import BackendTask.Env as Env
import BackendTask.Extra
import BackendTask.File as File
import BackendTask.Glob as Glob
import Cli.Option
import Cli.OptionsParser exposing (OptionsParser)
import Cli.OptionsParser.BuilderState
import Cli.Program
import Dict exposing (Dict)
import Elm.Module
import Elm.Package
import Elm.Parser
import Elm.Project
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node as Node
import Elm.Syntax.Qualified as Qualified
import Elm.Syntax.Qualified.Utils
import Elm.Syntax.Range exposing (Range)
import Elm.Version
import FatalError exposing (FatalError)
import List.Extra
import Pages.Script as Script exposing (Script)
import Parser
import Parser.Error
import Set exposing (Set)


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
    Do.each sourceDirectories
        (\dir ->
            Glob.fromString (dir ++ "/**/*.elm")
                |> BackendTask.map
                    (List.map
                        (\file ->
                            ( String.slice (String.length dir + 1) -4 file
                                |> String.split "/"
                            , file
                            )
                        )
                    )
        )
    <| \filesLists ->
    Do.do
        (BackendTask.Extra.foldl
            addDirectDependency
            (Qualified.initContext
                { packageName = Elm.Syntax.Qualified.Utils.authorProject }
            )
            application.depsDirect
        )
    <| \context ->
    filesLists
        |> List.concat
        |> checkModules Elm.Syntax.Qualified.Utils.authorProject context
        |> BackendTask.map (\_ -> ())


addDirectDependency :
    ( Elm.Package.Name, Elm.Version.Version )
    -> Qualified.PackageContext
    -> BackendTask FatalError Qualified.PackageContext
addDirectDependency ( packageName, packageVersion ) context =
    let
        elmVersion : String
        elmVersion =
            "0.19.1"
    in
    Do.allowFatal (Env.expect "ELM_HOME") <| \elmHome ->
    let
        path : String
        path =
            [ elmHome
            , elmVersion
            , "packages"
            , Elm.Package.toString packageName
            , Elm.Version.toString packageVersion
            ]
                |> String.join "/"
    in
    Do.log ("Adding dependency: " ++ Elm.Package.toString packageName) <| \() ->
    Do.allowFatal (File.jsonFile Elm.Project.decoder (path ++ "/elm.json")) <| \elmJson ->
    case elmJson of
        Elm.Project.Application _ ->
            -- Should not happen
            BackendTask.fail (FatalError.fromString "Cannot depend on an application")

        Elm.Project.Package package ->
            let
                exposed : List Elm.Module.Name
                exposed =
                    case package.exposed of
                        Elm.Project.ExposedList modules ->
                            modules

                        Elm.Project.ExposedDict list ->
                            List.concatMap Tuple.second list
            in
            BackendTask.Extra.foldl (addDependencyModule packageName path) context exposed


addDependencyModule :
    Elm.Package.Name
    -> String
    -> Elm.Module.Name
    -> Qualified.PackageContext
    -> BackendTask FatalError Qualified.PackageContext
addDependencyModule packageName path name context =
    let
        moduleName : ModuleName
        moduleName =
            Elm.Module.toString name
                |> String.split "."
    in
    Do.log ("  Adding module " ++ Elm.Module.toString name) <| \() ->
    Do.allowFatal (File.rawFile (path ++ "/src/" ++ String.join "/" moduleName ++ ".elm")) <| \fileString ->
    case Elm.Parser.parseToFile fileString of
        Ok file ->
            Qualified.addModule
                packageName
                moduleName
                (Qualified.unqualifiedToModuleInterface file)
                context
                |> Ok
                |> BackendTask.fromResult

        Err e ->
            parseErrorToFatalError fileString e
                |> Err
                |> BackendTask.fromResult


checkModules : Elm.Package.Name -> Qualified.PackageContext -> List ( ModuleName, String ) -> BackendTask FatalError Qualified.PackageInterface
checkModules packageName initialContext initialQueue =
    let
        localNames : Set ModuleName
        localNames =
            initialQueue
                |> List.map Tuple.first
                |> Set.fromList

        -- TODO: this is currently O(n l) where n is the number of modules and l is the maximum
        -- import depth. In practice l is `log n` but in theory it could be O(n)
        go :
            Bool
            -> List String
            -> Qualified.PackageInterface
            -> Qualified.PackageContext
            -> List String
            -> BackendTask FatalError Qualified.PackageInterface
        go addedAny delayed moduleDict context queue =
            case queue of
                [] ->
                    if List.isEmpty delayed then
                        BackendTask.succeed moduleDict

                    else if addedAny then
                        go False [] moduleDict context delayed

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
                                newContext : Qualified.PackageContext
                                newContext =
                                    Qualified.addModule packageName moduleName moduleInterface context

                                moduleInterface : Qualified.ModuleInterface
                                moduleInterface =
                                    Qualified.toModuleInterface qualified

                                moduleName : ModuleName
                                moduleName =
                                    Node.value qualified.moduleName

                                newModuleDict : Dict ModuleName Qualified.ModuleInterface
                                newModuleDict =
                                    Dict.insert moduleName moduleInterface moduleDict
                            in
                            go True delayed newModuleDict newContext tail

                        Err ( range, Qualified.ModuleNotFound moduleName ) ->
                            if Set.member moduleName localNames then
                                go addedAny (head :: delayed) moduleDict context tail

                            else
                                formatError
                                    { filename = head
                                    , file = fileString
                                    , range = range
                                    , message =
                                        "missing module: "
                                            ++ String.join "." moduleName
                                            ++ "\nAvailable: "
                                            ++ String.join ", " (List.map (String.join ".") (Set.toList localNames))
                                    }

                        Err ( range, Qualified.ModuleNameIsAmbiguous moduleName alts ) ->
                            formatError
                                { filename = head
                                , file = fileString
                                , range = range
                                , message =
                                    "module name `"
                                        ++ String.join "." moduleName
                                        ++ "` is ambiguous between: "
                                        ++ String.join ", " (List.map Elm.Package.toString alts)
                                }

                        Err ( range, Qualified.ValueIsAmbiguous name alts ) ->
                            formatError
                                { filename = head
                                , file = fileString
                                , range = range
                                , message =
                                    "value `"
                                        ++ name
                                        ++ "` is ambiguous between: "
                                        ++ String.join ", " (List.map Elm.Package.toString alts)
                                }

                        Err ( range, Qualified.InvalidSyntax ) ->
                            formatError
                                { filename = head
                                , file = fileString
                                , range = range
                                , message = "invalid syntax"
                                }

                        Err ( range, Qualified.ValueNotFound moduleName typeName ) ->
                            formatError
                                { filename = head
                                , file = fileString
                                , range = range
                                , message = "type not found: " ++ String.join "." (moduleName ++ [ typeName ])
                                }

                        Err ( range, Qualified.UnqualifiedNameNotFound name ) ->
                            formatError
                                { filename = head
                                , file = fileString
                                , range = range
                                , message = "value not found: " ++ name
                                }
    in
    go False [] Dict.empty initialContext (List.map Tuple.second initialQueue)


formatError :
    { filename : String
    , file : String
    , range : Range
    , message : String
    }
    -> BackendTask FatalError e
formatError { filename, file, range, message } =
    let
        context : number
        context =
            3

        split : List String
        split =
            file
                |> String.lines
                |> List.drop (range.start.row - context - 1)

        ( before, atAndAfter ) =
            List.Extra.splitAt (min context (range.start.row - 1)) split

        ( at, afterAndTail ) =
            atAndAfter
                |> List.Extra.splitAt
                    (range.end.row - range.start.row + 1)

        after : List String
        after =
            afterAndTail |> List.take context

        source : String
        source =
            before
                ++ List.map (Ansi.Color.fontColor Ansi.Color.red) at
                ++ after
                |> String.join "\n"
    in
    ("In file "
        ++ filename
        ++ ":"
        ++ String.fromInt range.start.row
        ++ ", "
        ++ message
        ++ "\n\n"
        ++ source
    )
        |> FatalError.fromString
        |> BackendTask.fail


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
