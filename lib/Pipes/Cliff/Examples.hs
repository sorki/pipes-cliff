-- | Examples using "Pipes.Cliff".  You will want to look at the
-- source code itself; viewing just the Haddocks will not help you
-- much.  You can view the source using Haddock if you used
-- @--hyperlink-source@ when building the library or if you are
-- viewing this on Hackage; look for the @Source@ link.  Or, you can
-- find the source at
--
-- <https://github.com/massysett/pipes-cliff/blob/master/lib/Pipes/Cliff/Examples.hs>
--
-- __Be sure to use the @-threaded@ option__ when compiling code that
-- uses "Pipes.Cliff", including this code; see the warning in
-- "Pipes.Cliff" for more details.

module Pipes.Cliff.Examples where

import Pipes.Cliff
import qualified Pipes.Prelude as P
import qualified Data.ByteString.Char8 as BS8

-- | Streams an infinite list of numbers to @less@.
-- The 'Effect' that streams values to the process is run in the
-- background by using 'conveyor', even though there is only one
-- subprocess.  This is typically what you want.  Shows off how you
-- can use "Pipes.Cliff" even for non-finite 'Producer's.  Don't try
-- to go to the end of the input in @less@, though.  When you quit
-- @less@, you will get broken pipe warnings printed to standard
-- error.  This is normal.  To suppress them, see the 'handler'
-- option.

numsToLess :: IO ()
numsToLess = runCliff $ produceNumbers >-> toLess
  where
    toLess = pipeInput Inherit Inherit (procSpec "less" [])

-- | Like 'numsToLess' but also returns the exit code from the @less@
-- process.
numsToLessWithExitCode :: IO ExitCode
numsToLessWithExitCode = runSafeT $ do
  hanMVar <- liftIO newEmptyMVar
  let spec = (procSpec "less" []) { storeProcessHandle = Just hanMVar }
      toLess = pipeInput Inherit Inherit spec
  runEffect (produceNumbers >-> toLess)
  han <- liftIO $ takeMVar hanMVar
  liftIO $ waitForProcess han


-- | Produces a stream of 'BS8.ByteString', where each
-- 'BS8.ByteString' is a shown integer.

produceNumbers :: Monad m => Producer BS8.ByteString m ()
produceNumbers = each . fmap mkNumStr $ [(0 :: Int) ..]
  where
    mkNumStr = flip BS8.snoc '\n' . BS8.pack . show


-- | Streams an infinite list of numbers to @tr@ and then to @less@.
-- Perfectly useless, but shows how to build pipelines.  Notice how
-- only one pipeline runs in the foreground; the other one runs in the
-- background.  You want to make sure that there is, at most, only one
-- pipeline in the foreground; otherwise, data will not stream between
-- the components of your pipeline.  You could put all components of
-- the pipeline in the background, but then remember that the 'Effect'
-- will immediately shut down and kill the child processes and threads
-- without even allowing the processes to finish streaming, which is
-- probably not what you want.  In such a case you could use
-- 'waitForProcess' in conjunction with 'storeProcessHandle' to wait
-- for a process in the pipeline to finish.

alphaNumbers :: IO ()
alphaNumbers = runSafeT $ do
  (toTr, fromTr) <- pipeInputOutput Inherit
    (procSpec "tr" ["[0-9]", "[a-z]"])
  let toLess = pipeInput Inherit Inherit
        (procSpec "less" [])
  conveyor $ produceNumbers >-> toTr
  runEffect $ fromTr >-> toLess

-- | Produces an infinite stream of numbers, sends it to @tr@ for some
-- mangling, and then to @sh@, which will copy each line both to
-- standard output and to standard error.  From @sh@, standard output
-- is then sent off to @less@, and standard error is sent to a
-- separate thread which will collect the results and return them.
--
-- This example shows you how to write a pipeline that deals with
-- both standard output and standard error.
--
-- It's also interesting to note here that because of the buffering
-- that happens in various places throughout the pipeline, and because
-- less itself also buffers its input, the output you will see from
-- the @sh@ process's standard error will be much longer than the
-- output the user actually viewed in @less@.
standardOutputAndError :: IO BS8.ByteString
standardOutputAndError = runSafeT $ do
  (toTr, fromTr) <- pipeInputOutput Inherit
    (procSpec "tr" ["[0-9]", "[a-z]"])
  (toSh, fromShOut, fromShErr) <- pipeInputOutputError
    (procSpec "sh" ["-c", script])
  let toLess = pipeInput Inherit Inherit (procSpec "less" [])
  conveyor $ produceNumbers >-> toTr
  conveyor $ fromTr >-> toSh
  conveyor $ fromShOut >-> toLess
  P.fold BS8.append BS8.empty id fromShErr
  where
    script = "while read line; do echo $line; echo $line 1>&2; done"

-- | Like 'alphaNumbers' but just sends a limited number
-- of numbers to @cat@.  A useful test to make sure that pipelines
-- shut down automatically.  Runs both pipelines in the background and
-- uses 'waitForProcess' to wait until @cat@ is done.  If you ran both
-- pipelines in the background but did not use 'waitForProcess', the
-- pipeline would terminate immediately.
limitedAlphaNumbers :: IO ExitCode
limitedAlphaNumbers = runSafeT $ do
  (toTr, fromTr) <- pipeInputOutput Inherit
    (procSpec "tr" ["[0-9]", "[a-z]"])
  catHanMVar <- liftIO newEmptyMVar
  let toCat = pipeInput Inherit Inherit
              (procSpec "cat" []) { storeProcessHandle = Just catHanMVar }
  conveyor $ ((produceNumbers >-> P.take 300 >-> toTr) >> liftIO (putStrLn "done conveying"))
  conveyor $ ((fromTr >-> toCat) >> liftIO (putStrLn "done conveying again"))
  han <- liftIO $ takeMVar catHanMVar
  liftIO $ waitForProcess han

-- | Produces a finite list of numbers, sends it to @tr@ for some
-- mangling, and then puts the results into a 'BS8.ByteString' for
-- further processing.  This example shows how you can use this
-- library to place the results of a pipeline into a simple strict
-- data type.
alphaNumbersByteString :: IO BS8.ByteString
alphaNumbersByteString = runSafeT $ do
  (toTr, fromTr) <- pipeInputOutput Inherit
    (procSpec "tr" ["[0-9]", "[a-z]"])
  conveyor $ produceNumbers >-> P.take 300 >-> toTr
  P.fold BS8.append BS8.empty id fromTr
