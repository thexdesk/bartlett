{-# LANGUAGE DuplicateRecordFields #-}

{-|
Module      : Network
Description : General network related methods used throughout Bartlett
Copyright   : (c) Nike, Inc., 2016
License     : BSD3
Maintainer  : fernando.freire@nike.com
Stability   : stable
General network related methods used throughout Bartlett.
-}
module Bartlett.Network (
  -- * Request handlers
  execRequest,
  -- * Error Handlers
  simpleErrorHandler,
  recoverableErrorHandler
)where

import Bartlett.Util (uriToString, toResponseStatus, withForcedSSL)
import Bartlett.Types (RequestType(Get, Post), JenkinsInstance)

import qualified Control.Exception as E
import Data.Aeson.Encode.Pretty (encodePretty)
import Data.ByteString.Lazy.Char8 (ByteString, unpack)
import Data.Maybe (fromMaybe)
import qualified Network.HTTP.Client as NHC
import System.Exit (die)
import Network.Wreq (Options, Response)
import qualified Network.Wreq.Session as S

-- | General request handler that provides basic error handling.
execRequest ::
  RequestType                 -- ^ The type of request to make
  -> Options                  -- ^ Request params to pass along with the request.
  -> JenkinsInstance               -- ^ The uri to make the request to
  -> Maybe ByteString         -- ^ The file to upload to the Jenkins instance.
  -> IO (Response ByteString)
execRequest requestType opts reqUrl postBody =
  S.withAPISession $ \session ->
    case requestType of
      -- TODO Need to get a CSRF crumb
      -- JENKINS_URL/crumbIssuer/api/json?xpath=?xpath=concat(//crumbRequestField,":",//crumb)')
      Post ->
        postSession reqUrl
          `E.catch`
            recoverableErrorHandler (postSession $ withForcedSSL reqUrl)
              where fileToUpload = fromMaybe "" postBody :: ByteString
                    postSession url = S.postWith opts session (uriToString url) fileToUpload
      Get ->
        getSession reqUrl
          `E.catch`
            recoverableErrorHandler (getSession . withForcedSSL $ reqUrl)
              where getSession url = S.getWith opts session (uriToString url)


-- | Handler that returns a JSON representation of the error status.
simpleErrorHandler :: NHC.HttpException -> IO a
simpleErrorHandler (NHC.StatusCodeException status _ _) =
  die . unpack . encodePretty . toResponseStatus $ status

-- | Attempt to recover from non-fatal errors with the provided action, otherwise
--   fail again with the 'simpleErrorHandler'
recoverableErrorHandler :: IO a -> NHC.HttpException -> IO a
recoverableErrorHandler a e =
  case e of
    (NHC.InvalidUrlException _ _) ->
      -- Retry with the given IO action
      a `E.catch` simpleErrorHandler
    _ -> -- Otherwise fall through to the simple error handler
      simpleErrorHandler e
