{-# LANGUAGE DeriveGeneric       #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies        #-}
module Lib where

import           Control.Monad.Trans
import           Crypto.Hash                    ( Digest
                                                , SHA256
                                                , digestFromByteString
                                                )
import           Crypto.Hash.SHA256
import           Text.Read                      (readMaybe)
import           Data.Aeson
import           Data.Binary
import           Data.ByteString.Char8          (pack)
import           Data.Time.Clock.POSIX
import           GHC.Generics
import           Text.PrettyPrint.GenericPretty

-- the main data type for our blockchain
data Block = Block { index        :: Int
                   , previousHash :: String
                   , timestamp    :: Int
                   , blockData    :: String
                   , nonce        :: Int
                   , blockHash    :: String
                   } deriving (Show, Read, Eq, Generic)

-- http params to add a block to the chain
newtype BlockArgs = BlockArgs{blockBody :: String}
                  deriving (Show, Eq, Generic)

instance ToJSON BlockArgs
instance FromJSON BlockArgs
instance ToJSON Block
instance FromJSON Block
instance Binary Block
instance Out Block

-- unix timestamp as an int
epoch :: IO Int
epoch = round `fmap` getPOSIXTime

-- hashes a string and returns a hex digest
sha256 :: String -> Maybe (Digest SHA256)
sha256 = digestFromByteString . hash . pack

-- abstracted hash function that takes a string
-- to hash and returns a hex string
hashString :: String -> String
hashString =
  maybe (error "Something went wrong generating a hash") show . sha256

calculateBlockHash :: Block -> String
calculateBlockHash (Block i p t b n _)  =
  hashString $ concat [show i, p, show t, b, show n]

-- returns a copy of the block with the hash set
setBlockHash :: Block -> Block
setBlockHash block = block {blockHash = calculateBlockHash block}

-- returns a copy of the block with a valid nonce and hash set
setNonceAndHash :: Block -> Block
setNonceAndHash block = setBlockHash $ block {nonce = findNonce block}

-- Rudimentary proof-of-work (POW): ensures that a block hash
-- is less than a certain value (i.e. contains a certain
-- amount of leading zeroes).
-- In our case, it's 4 leading zeroes. We're using the Integer type
-- since the current target is higher than the max for Int.
-- POW is useful because with this imposed difficulty to add values to
-- the blockchain, it becomes exponentially less feasible to edit the
-- chain - one would need to regenerate an entirely new valid chain
-- after the edited block(s)
difficultyTarget :: Integer
difficultyTarget =
  0x0000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff

-- checks whether the provided block hash satisfies
-- our PoW requirement
satisfiesPow :: String -> Bool
satisfiesPow bHash =
  maybe
    (error $ "Something is wrong with the provided hash: " ++ bHash)
    (< difficultyTarget)
    (readMaybe ("0x" ++ bHash) :: Maybe Integer)

-- Recursively finds a nonce that satisfies the difficulty target
-- If our blockHash already satisfies the PoW, return the current nonce
-- If not, increment the nonce and try again
-- TODO - Handle nonce overflow.
findNonce :: Block -> Int
findNonce block = do
  let bHash = calculateBlockHash block
      currentNonce = nonce block
  if satisfiesPow bHash
    then currentNonce
    else findNonce $ block {nonce = currentNonce + 1}

-- a hardcoded initial block, we need this to make sure all
-- nodes have the same starting point, so we have a hard coded
-- frame of reference to detect validity
initialBlock :: Block
initialBlock = do
  let block = Block 0 "0" 0 "initial data" 0 ""
  setNonceAndHash block

-- a new block is valid if its index is 1 higher, its
-- previous hash points to our last block, and its hash is computed
-- correctly
isValidNewBlock :: Block -> Block -> Bool
isValidNewBlock prev next
  | index prev + 1 == index next &&
    blockHash prev == previousHash next &&
    blockHash next == calculateBlockHash next &&
    satisfiesPow (blockHash next) = True
  | otherwise = False

-- a chain is valid if it starts with our hardcoded initial
-- block and every block is valid with respect to the previous
isValidChain :: [Block] -> Bool
isValidChain chain = case chain of
  [] -> True
  [x] -> x == initialBlock
  (x:xs) ->
    let blockPairs = zip chain xs in
      x == initialBlock &&
      all (uncurry isValidNewBlock) blockPairs

-- return the next block given a previous block and some data to put in it
mineBlockFrom :: (MonadIO m) => Block -> String -> m Block
mineBlockFrom lastBlock stringData = do
  time <- liftIO epoch
  let block = Block { index        = index lastBlock + 1
                    , previousHash = blockHash lastBlock
                    , timestamp    = time
                    , blockData    = stringData
                    , nonce        = 0
                    , blockHash    = "will be changed"
                    }
  return $ setNonceAndHash block
