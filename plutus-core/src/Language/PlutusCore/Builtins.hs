{-# OPTIONS_GHC -fno-warn-redundant-constraints #-}

{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE DeriveAnyClass    #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications  #-}
{-# LANGUAGE TypeFamilies      #-}
{-# LANGUAGE TypeOperators     #-}

module Language.PlutusCore.Builtins where

import           Language.PlutusCore.Constant.Meaning
import           Language.PlutusCore.Constant.Typed
import           Language.PlutusCore.Evaluation.Machine.ExBudgeting
import           Language.PlutusCore.Evaluation.Machine.ExMemory
import           Language.PlutusCore.Evaluation.Result
import           Language.PlutusCore.Universe

import           Codec.CBOR.Decoding
import           Codec.CBOR.Encoding
import           Codec.Serialise
import           Control.DeepSeq
import           Crypto
import qualified Data.ByteString                                    as BS
import qualified Data.ByteString.Hash                               as Hash
import           Data.Hashable
import           Data.Ix
import           Data.Text.Prettyprint.Doc
import           Debug.Trace                                        (traceIO)
import           GHC.Generics
import           System.IO.Unsafe

-- TODO: I think we should have the following structure:
--
-- Language.PlutusCore.Default.Universe
-- Language.PlutusCore.Default.Builtins
--
-- and
--
-- Language.PlutusCore.Default
--
-- reexporting stuff from these two.

-- | Default built-in functions.
data DefaultFun
    = AddInteger
    | SubtractInteger
    | MultiplyInteger
    | DivideInteger
    | QuotientInteger
    | RemainderInteger
    | ModInteger
    | LessThanInteger
    | LessThanEqInteger
    | GreaterThanInteger
    | GreaterThanEqInteger
    | EqInteger
    | Concatenate
    | TakeByteString
    | DropByteString
    | SHA2
    | SHA3
    | VerifySignature
    | EqByteString
    | LtByteString
    | GtByteString
    | IfThenElse
    | CharToString
    | Append
    | Trace
    deriving (Show, Eq, Ord, Enum, Bounded, Generic, NFData, Hashable, Ix)

-- TODO: do we really want function names to be pretty-printed differently to what they are named as
-- constructors of 'DefaultFun'?
instance Pretty DefaultFun where
    pretty AddInteger           = "addInteger"
    pretty SubtractInteger      = "subtractInteger"
    pretty MultiplyInteger      = "multiplyInteger"
    pretty DivideInteger        = "divideInteger"
    pretty QuotientInteger      = "quotientInteger"
    pretty ModInteger           = "modInteger"
    pretty RemainderInteger     = "remainderInteger"
    pretty LessThanInteger      = "lessThanInteger"
    pretty LessThanEqInteger    = "lessThanEqualsInteger"
    pretty GreaterThanInteger   = "greaterThanInteger"
    pretty GreaterThanEqInteger = "greaterThanEqualsInteger"
    pretty EqInteger            = "equalsInteger"
    pretty Concatenate          = "concatenate"
    pretty TakeByteString       = "takeByteString"
    pretty DropByteString       = "dropByteString"
    pretty EqByteString         = "equalsByteString"
    pretty LtByteString         = "lessThanByteString"
    pretty GtByteString         = "greaterThanByteString"
    pretty SHA2                 = "sha2_256"
    pretty SHA3                 = "sha3_256"
    pretty VerifySignature      = "verifySignature"
    pretty IfThenElse           = "ifThenElse"
    pretty CharToString         = "charToString"
    pretty Append               = "append"
    pretty Trace                = "trace"

instance ExMemoryUsage DefaultFun where
    memoryUsage _ = 1

newtype DefaultFunDyn = DefaultFunDyn
    { defaultFunDynTrace :: String -> IO ()
    }

instance Semigroup DefaultFunDyn where
    DefaultFunDyn trace1 <> DefaultFunDyn trace2 = DefaultFunDyn $ \str -> trace1 str `seq` trace2 str

instance Monoid DefaultFunDyn where
    mempty = DefaultFunDyn traceIO

-- | Turn a function into another function that returns 'EvaluationFailure' when its second argument
-- is 0 or calls the original function otherwise and wraps the result in 'EvaluationSuccess'.
-- Useful for correctly handling `div`, `mod`, etc.
nonZeroArg :: (Integer -> Integer -> Integer) -> Integer -> Integer -> EvaluationResult Integer
nonZeroArg _ _ 0 = EvaluationFailure
nonZeroArg f x y = EvaluationSuccess $ f x y

integerToInt :: Integer -> Int
integerToInt = fromIntegral

defaultFunMeaning
    :: ( HasConstantIn uni term, GShow uni, GEq uni
       , uni `IncludesAll` '[(), Bool, Integer, Char, String, BS.ByteString]
       )
    => DefaultFun -> BuiltinMeaning term DefaultFunDyn CostModel
defaultFunMeaning AddInteger =
    toStaticBuiltinMeaning
        ((+) @Integer)
        (runCostingFunTwoArguments . paramAddInteger)
defaultFunMeaning SubtractInteger =
    toStaticBuiltinMeaning
        ((-) @Integer)
        (runCostingFunTwoArguments . paramSubtractInteger)
defaultFunMeaning MultiplyInteger =
    toStaticBuiltinMeaning
        ((*) @Integer)
        (runCostingFunTwoArguments . paramMultiplyInteger)
defaultFunMeaning DivideInteger =
    toStaticBuiltinMeaning
        (nonZeroArg div)
        (runCostingFunTwoArguments . paramDivideInteger)
defaultFunMeaning QuotientInteger =
    toStaticBuiltinMeaning
        (nonZeroArg quot)
        (runCostingFunTwoArguments . paramQuotientInteger)
defaultFunMeaning RemainderInteger =
    toStaticBuiltinMeaning
        (nonZeroArg rem)
        (runCostingFunTwoArguments . paramRemainderInteger)
defaultFunMeaning ModInteger =
    toStaticBuiltinMeaning
        (nonZeroArg mod)
        (runCostingFunTwoArguments . paramModInteger)
defaultFunMeaning LessThanInteger =
    toStaticBuiltinMeaning
        ((<) @Integer)
        (runCostingFunTwoArguments . paramLessThanInteger)
defaultFunMeaning LessThanEqInteger =
    toStaticBuiltinMeaning
        ((<=) @Integer)
        (runCostingFunTwoArguments . paramLessThanEqInteger)
defaultFunMeaning GreaterThanInteger =
    toStaticBuiltinMeaning
        ((>) @Integer)
        (runCostingFunTwoArguments . paramGreaterThanInteger)
defaultFunMeaning GreaterThanEqInteger =
    toStaticBuiltinMeaning
        ((>=) @Integer)
        (runCostingFunTwoArguments . paramGreaterThanEqInteger)
defaultFunMeaning EqInteger =
    toStaticBuiltinMeaning
        ((==) @Integer)
        (runCostingFunTwoArguments . paramEqInteger)
defaultFunMeaning Concatenate =
    toStaticBuiltinMeaning
        BS.append
        (runCostingFunTwoArguments . paramConcatenate)
defaultFunMeaning TakeByteString =
    toStaticBuiltinMeaning
        (BS.take . integerToInt)
        (runCostingFunTwoArguments . paramTakeByteString)
defaultFunMeaning DropByteString =
    toStaticBuiltinMeaning
        (BS.drop . integerToInt)
        (runCostingFunTwoArguments . paramDropByteString)
defaultFunMeaning SHA2 =
    toStaticBuiltinMeaning
        Hash.sha2
        (runCostingFunOneArgument . paramSHA2)
defaultFunMeaning SHA3 =
    toStaticBuiltinMeaning
        Hash.sha3
        (runCostingFunOneArgument . paramSHA3)
defaultFunMeaning VerifySignature =
    toStaticBuiltinMeaning
        (verifySignature @EvaluationResult)
        (runCostingFunThreeArguments . paramVerifySignature)
defaultFunMeaning EqByteString =
    toStaticBuiltinMeaning
        ((==) @BS.ByteString)
        (runCostingFunTwoArguments . paramEqByteString)
defaultFunMeaning LtByteString =
    toStaticBuiltinMeaning
        ((<) @BS.ByteString)
        (runCostingFunTwoArguments . paramLtByteString)
defaultFunMeaning GtByteString =
    toStaticBuiltinMeaning
        ((>) @BS.ByteString)
        (runCostingFunTwoArguments . paramGtByteString)
defaultFunMeaning IfThenElse =
    toStaticBuiltinMeaning
        ((\b x y -> if b then x else y) :: a ~ Opaque term (TyVarRep "a" 0) => Bool -> a -> a -> a)
        (runCostingFunThreeArguments . paramIfThenElse)
defaultFunMeaning CharToString =
    toStaticBuiltinMeaning
        (pure :: Char -> String)
        mempty  -- TODO: budget.
defaultFunMeaning Append =
    toStaticBuiltinMeaning
        ((++) :: String -> String -> String)
        mempty  -- TODO: budget.
defaultFunMeaning Trace =
    toDynamicBuiltinMeaning
        (\env -> unsafePerformIO . defaultFunDynTrace env)
        mempty  -- TODO: budget.

-- See Note [Stable encoding of PLC]
instance Serialise DefaultFun where
    encode = encodeWord . \case
              AddInteger           -> 0
              SubtractInteger      -> 1
              MultiplyInteger      -> 2
              DivideInteger        -> 3
              RemainderInteger     -> 4
              LessThanInteger      -> 5
              LessThanEqInteger    -> 6
              GreaterThanInteger   -> 7
              GreaterThanEqInteger -> 8
              EqInteger            -> 9
              Concatenate          -> 10
              TakeByteString       -> 11
              DropByteString       -> 12
              SHA2                 -> 13
              SHA3                 -> 14
              VerifySignature      -> 15
              EqByteString         -> 16
              QuotientInteger      -> 17
              ModInteger           -> 18
              LtByteString         -> 19
              GtByteString         -> 20
              IfThenElse           -> 21
              CharToString         -> 22
              Append               -> 23
              Trace                -> 24

    decode = go =<< decodeWord
        where go 0  = pure AddInteger
              go 1  = pure SubtractInteger
              go 2  = pure MultiplyInteger
              go 3  = pure DivideInteger
              go 4  = pure RemainderInteger
              go 5  = pure LessThanInteger
              go 6  = pure LessThanEqInteger
              go 7  = pure GreaterThanInteger
              go 8  = pure GreaterThanEqInteger
              go 9  = pure EqInteger
              go 10 = pure Concatenate
              go 11 = pure TakeByteString
              go 12 = pure DropByteString
              go 13 = pure SHA2
              go 14 = pure SHA3
              go 15 = pure VerifySignature
              go 16 = pure EqByteString
              go 17 = pure QuotientInteger
              go 18 = pure ModInteger
              go 19 = pure LtByteString
              go 20 = pure GtByteString
              go 21 = pure IfThenElse
              go 22 = pure CharToString
              go 23 = pure Append
              go 24 = pure Trace
              go _  = fail "Failed to decode BuiltinName"
