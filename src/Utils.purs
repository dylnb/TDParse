module Utils where

import Control.Apply
import Data.List
import Data.Tuple

import Data.Function (flip)
import Data.Monoid ((<>))

apmplus = lift2 (<>)
infixr 6 apmplus as <+>

flippedApply = lift2 (flip apply)
infixl 5 flippedApply as <**>

one = flip any

infixr 0 Tuple as ^
infixr 0 type Tuple as ^