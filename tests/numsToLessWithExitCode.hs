module Main where

import Pipes.Cliff.Examples
import System.Exit

main :: IO ()
main = numsToLessWithExitCode >>= exitWith
