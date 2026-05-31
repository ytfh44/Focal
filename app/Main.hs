module Main (main) where

import Focal.Core
import Focal.Tuple
import Focal.List

main :: IO ()
main = do
  putStrLn "=== Focal Demo ==="
  
  -- Tuple focus
  let pair = (42 :: Int, "hello")
  putStrLn $ "Original: " ++ show pair
  putStrLn $ "After fstF (*2): " ++ show (overF fstF (*2) pair)
  putStrLn $ "After sndF reverse: " ++ show (overF sndF reverse pair)
  
  -- List element focus
  let xs = [1, 2, 3, 4, 5] :: [Int]
  putStrLn $ "Original list: " ++ show xs
  putStrLn $ "After element 2 (*10): " ++ show (overF (unsafeElementF 2) (*10) xs)
  
  putStrLn "Demo complete."