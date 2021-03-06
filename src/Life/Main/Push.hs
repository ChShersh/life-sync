{- |
Copyright:  (c) 2017-2020 Kowainik
SPDX-License-Identifier: MPL-2.0
Maintainer: Kowainik <xrom.xkov@gmail.com>

Functions to update the remote repository.
-}

module Life.Main.Push
    ( lifePush
    ) where

import Path (Abs, Path, Rel, toFilePath, (</>))
import Path.IO (doesDirExist, doesFileExist, removeDirRecur, removeFile)
import Relude.Extra.Lens ((^.))
import Validation (Validation (..))

import Life.Configuration (LifeConfiguration (..), directoriesL, filesL, lifeConfigMinus,
                           parseHomeLife, parseRepoLife)
import Life.Core (CommitMsg (..), master)
import Life.Github (updateDotfilesRepo, withSynced)
import Life.Main.Init (lifeInitQuestion)
import Life.Message (abortCmd)
import Life.Path (LifeExistence (..), relativeToHome, repoName, whatIsLife)

import qualified Data.Set as Set
import qualified Data.Text as Text


lifePush :: IO ()
lifePush = whatIsLife >>= \case
    OnlyRepo _ -> abortCmd "push" ".life file doesn't exist"
    OnlyLife _ -> abortCmd "push" "dotfiles file doesn't exist"
    NoLife     -> lifeInitQuestion "push" pushProcess
    Both _ _   -> withSynced master pushProcess
  where
    pushProcess :: IO ()
    pushProcess = do
        -- check that all from .life exist
        globalConf <- parseHomeLife
        checkLife globalConf >>= \case
            Failure msgs -> abortCmd "push" $
                "Following files/directories are missing:\n"
                <> Text.intercalate "\n" msgs
            Success _ -> do
                -- first, find the difference between repo .life and global .life
                repoConf <- parseRepoLife
                let removeConfig = lifeConfigMinus repoConf globalConf
                -- delete all redundant files from local dotfiles
                removeAll removeConfig

                -- copy from local files to repo including .life
                -- commmit & push
                updateDotfilesRepo (CommitMsg "Push updates") globalConf


    -- | checks if all the files/dirs from global .life exist.
    checkLife :: LifeConfiguration -> IO (Validation [Text] LifeConfiguration)
    checkLife lf = do
        eFiles <- traverse (withExist doesFileExist) $ Set.toList (lf ^. filesL)
        eDirs  <- traverse (withExist doesDirExist) $ Set.toList (lf ^. directoriesL)
        pure $ LifeConfiguration
            <$> checkPaths eFiles
            <*> checkPaths eDirs
            <*> Success (Last $ Just master)
      where
        withExist :: (Path Abs f -> IO Bool) -> Path Rel f -> IO (Path Rel f, Bool)
        withExist doesExist path = (path,) <$> (relativeToHome path >>= doesExist)

        checkPaths :: [(Path Rel f, Bool)] -> Validation [Text] (Set (Path Rel f))
        checkPaths = fmap Set.fromList . traverse checkPath

        checkPath :: (Path Rel t, Bool) -> Validation [Text] (Path Rel t)
        checkPath (f, is) = if is then Success f else Failure [toText (toFilePath f)]

    -- | removes all redundant files from repo folder.
    removeAll :: LifeConfiguration -> IO ()
    removeAll conf = do
        for_ (conf ^. filesL) $ \f ->
            relativeToHome (repoName </> f) >>= removeFile
        for_ (conf ^. directoriesL) $ \d ->
            relativeToHome (repoName </> d) >>= removeDirRecur
