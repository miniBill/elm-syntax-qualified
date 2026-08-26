module BackendTask.Extra exposing (foldl)

import BackendTask exposing (BackendTask)


foldl :
    (a
     -> b
     -> BackendTask error b
    )
    -> b
    -> List a
    -> BackendTask error b
foldl f s l =
    List.foldl
        (\e -> BackendTask.andThen (\a -> f e a))
        (BackendTask.succeed s)
        l
