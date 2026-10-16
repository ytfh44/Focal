module Main (main) where

import Test.DocTest (doctest)

main :: IO ()
main = doctest
  [ "-isrc"
  , "src/Focal/Core.hs"
  , "src/Focal/Tuple.hs"
  , "src/Focal/List.hs"
  , "src/Focal/Zipper.hs"
  , "src/Focal/Interop.hs"
  , "src/Focal/Partial.hs"
  , "src/Focal/Effectful.hs"
  , "src/Focal/Generic.hs"
  , "src/Focal/Optional.hs"
  ]
