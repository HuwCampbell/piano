{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}

import           Control.Monad.IO.Class (liftIO)
import           Control.Monad.Trans.Either (EitherT, hoistEither)
import           Control.Monad.Trans.Either.Exit (orDie)

import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as Char8
import qualified Data.ByteString.Lazy.Char8 as Lazy
import qualified Data.Vector as Boxed

import           P

import           Piano.Data
import           Piano.Foreign
import           Piano.Parser

import           System.IO (IO, FilePath, BufferMode(..))
import           System.IO (hSetBuffering, stdout, stderr, putStrLn, print)
import           System.Exit (exitSuccess)

import           X.Options.Applicative (Parser, Mod, CommandFields)
import           X.Options.Applicative (SafeCommand(..), RunType(..))
import           X.Options.Applicative (dispatch, safeCommand, command')
import           X.Options.Applicative (help, metavar, argument, str, subparser)


data PianoCommand =
    PianoCheck !FilePath
  | PianoLookup !FilePath
    deriving (Eq, Show)

data PianoError =
    PianoParserError !ParserError
    deriving (Eq, Ord, Show)

renderPianoError :: PianoError -> Text
renderPianoError = \case
  PianoParserError err ->
    renderParserError err

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  hSetBuffering stderr LineBuffering
  dispatch parser >>= \sc ->
    case sc of
      VersionCommand ->
        putStrLn "0.1" >> exitSuccess
      DependencyCommand ->
        mapM_ putStrLn []
      RunCommand DryRun c ->
        print c >> exitSuccess
      RunCommand RealRun c ->
        orDie renderPianoError $ run c

parser :: Parser (SafeCommand PianoCommand)
parser =
  safeCommand . subparser . mconcat $ commands

commands :: [Mod CommandFields PianoCommand]
commands = [
    command' "check" "Validate that a chord descriptor can be loaded." pPianoCheck
  , command' "lookup" "Lookup entities passed to stdin." pPianoLookup
  ]

pPianoCheck :: Parser PianoCommand
pPianoCheck =
  PianoCheck
    <$> pDescriptor

pPianoLookup :: Parser PianoCommand
pPianoLookup =
  PianoLookup
    <$> pDescriptor

pDescriptor :: Parser FilePath
pDescriptor =
  argument str $
    metavar "PATH" <>
    help "The path to a chord descriptor"

run :: PianoCommand -> EitherT PianoError IO ()
run = \case
  PianoCheck path -> do
    bs <- liftIO $ B.readFile path
    _ <- firstT PianoParserError . hoistEither $ parsePiano bs
    pure ()
  PianoLookup path -> do
    bs <- liftIO $ B.readFile path
    piano <- firstT PianoParserError . hoistEither $ parsePiano bs
    fpiano <- liftIO $ newForeignPiano piano
    lines <- liftIO $ fmap Lazy.toStrict . Lazy.lines <$> Lazy.getContents
    liftIO . for_ lines $ \entity -> do
      mEndTimes <- lookup fpiano entity
      case mEndTimes of
        Nothing ->
          putStrLn "<not found>"
        Just endTimes ->
          Char8.putStrLn . Char8.intercalate "|" . fmap (renderDate . fromExclusive . labelTime) $ Boxed.toList endTimes
