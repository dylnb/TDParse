
module TDParseCFG where

import Data.Enum
import Data.List
import Data.Maybe
import Data.Tuple
import Memo
import Prelude hiding ((#), (*))
import Debug

import Control.Alternative (guard)
import Control.Apply (lift2)
import Control.Lazy (fix)
import Data.Bounded.Generic (genericBottom, genericTop)
import Data.Enum.Generic (genericPred, genericSucc)
import Data.Foldable (lookup)
import Data.Generic.Rep (class Generic)
import Data.Show.Generic (genericShow)
-- import Data.String as DS
import Data.String.Utils (words)
import Data.Traversable (sequence, traverse)
import LambdaCalc -- (Term(..), eval, make_var, (!), (%), _1, _2, (*), (|?), set, get_dom, get_rng, make_set, conc)
import Utils ((<**>), (<+>), (^), type (^))


{- Datatypes for syntactic and semantic composition-}

-- some syntactic categories
data Cat
  = CP | Cmp -- Clauses and Complementizers
  | CBar | DBar | Cor -- Coordinators and Coordination Phrases
  | DP | Det | Gen | Dmp -- (Genitive) Determiners and Determiner Phrases
  | NP | TN -- Transitive (relational) Nouns and Noun Phrases
  | VP | TV | DV | AV -- Transitive, Ditransitive, and Attitude Verbs and Verb Phrases
  | AdjP | TAdj | Deg | AdvP | TAdv -- Modifiers
derive instance Eq Cat
derive instance Ord Cat
derive instance Generic Cat _
instance Show Cat where
  show = genericShow
instance Enum Cat where
  succ = genericSucc
  pred = genericPred
instance Bounded Cat where
  top = genericTop
  bottom = genericBottom

-- semantic types
data Ty
  = E | T         -- Base types
  | Arr Ty Ty     -- Functions
  | Eff F Ty      -- F-ectful
derive instance Eq Ty
derive instance Ord Ty
derive instance Generic Ty _
instance Show Ty where
  show t = genericShow t

infixr 1 Arr as :->

-- Effects
data F = S | R Ty | W Ty | C Ty Ty | U
derive instance Ord F
derive instance Generic F _
instance Show F where
  show = genericShow

instance Eq F where
  eq U _ = true
  eq _ U = true
  eq S S = true
  eq (R t) (R u) = t == u
  eq (W t) (W u) = t == u
  eq (C t u) (C v w) = t == v && u == w
  eq _  _ = false

showNoIndices :: F -> String
showNoIndices = case _ of
  S     -> "S"
  R _   -> "R"
  W _   -> "W"
  C _ _ -> "C"
  U     -> "_"

-- convenience constructors
effS     = Eff S
effR r   = Eff (R r)
effW w   = Eff (W w)
effC r o = Eff (C r o)

atomicTypes = E : T : Nil
atomicEffects =
  pure S <> (R <$> atomicTypes) <> (W <$> atomicTypes) <> (lift2 C atomicTypes atomicTypes)

{- Syntactic parsing -}

-- A (binary-branching) grammar is a list of production rules, telling
-- you what new categories you can build out of ones you are handed
type CFG = Cat -> Cat -> List Cat

-- Our syntactic objects are (binary-branching) constituency trees with
-- typed leaves
data Syn
  = Leaf String Term Ty
  | Branch Syn Syn

-- Phrases to be parsed are lists of "signs" whose various morphological
-- spellouts, syntactic categories, and types are known
type Sense = (Term ^ Cat ^ Ty) -- a single sense of a single word
type Word = String ^ List Sense              -- a word may have several senses
type Phrase = List Word
type Lexicon = List Word

-- a simple memoized chart parser, parameterized to a particular grammar
protoParse ::
  forall m. Monad m
  => CFG
  -> (Int ^ Int ^ Phrase -> m (List (Cat ^ Syn)))
  ->  Int ^ Int ^ Phrase -> m (List (Cat ^ Syn))
protoParse _   _ (_^_^(s^sign):Nil) =
  pure $ map (\(d^c^t) -> c ^ Leaf s d t) sign
protoParse cfg f phrase =
  concat <$> traverse help (bisect phrase)
  where
    bisect (lo ^ hi ^ u) = do
      i <- 1 .. (length u - 1)
      let (ls ^ rs) = take i u ^ drop i u
      pure $ (lo ^ (lo + i - 1) ^ ls) ^ ((lo + i) ^ hi ^ rs)

    help (ls ^ rs) = do
      parsesL <- f ls
      parsesR <- f rs
      pure $ do
        lcat ^ lsyn <- parsesL
        rcat ^ rsyn <- parsesR
        cat <- cfg lcat rcat
        pure $ cat ^ Branch lsyn rsyn

-- Return all the grammatical constituency structures of a phrase by parsing it
-- and throwing away the category information
parse :: CFG -> Lexicon -> String -> Maybe (List Syn)
parse cfg lex input = do
  ws <- traverse (\s -> map (s ^ _) $ lookup s lex) <<< fromFoldable $ words input
  pure $ snd <$> memo (protoParse cfg) (0 ^ length ws - 1 ^ ws)

-- A semantic object is either a lexical entry or a mode of combination applied to
-- two other semantic objects
data Sem
  = Lex Term
  | Comb Mode Term
derive instance Eq Sem
derive instance Generic Sem _
instance Show Sem where
  show t = genericShow t

-- Modes of combination
type Mode = List Op
data Op
  = FA | BA | PM | FC -- Base        > < & .
  | MR F | ML F       -- Functor     fmap
  | UR F | UL F       -- Applicative pure
  | A F               -- Applicative <*>
  | J F               -- Monad       join
  | Eps               -- Adjoint     counit
  | D                 -- Cont        lower
  | XL F Op           -- Comonad     extend
derive instance Eq Op
derive instance Generic Op _
instance Show Op where
  show = case _ of
    FA   -> ">"
    BA   -> "<"
    PM   -> "&"
    FC   -> "."
    MR f -> "R"  -- <> " " <> show f
    ML f -> "L"  -- <> " " <> show f
    UL f -> "UL" -- <> " " <> show f
    UR f -> "UR" -- <> " " <> show f
    A f  -> "A"  -- <> " " <> show f
    J f  -> "J"  -- <> " " <> show f
    Eps  -> "Eps"
    D    -> "D"
    XL f o -> "XL" <> " " <> show o


{- Type classes -}

-- You could implement some real logic here if you wanted,
-- but all our Effects are indeed Functors, and all but (W E) are
-- indeed Applicative and Monadic
-- The only adjunction we demonstrate is that between W and R
functor _       = true
appl    f@(W w) = functor f && monoid w
appl    f       = functor f && true
monad   f       = appl f && true

monoid T = true
monoid _ = false

adjoint (W i) (R j) = i == j
adjoint _ _         = false

class Commute f where
  commutative :: f -> Boolean
instance Commute Ty where
  commutative ty = ty == T
instance Commute F where
  commutative = case _ of
    S     -> true
    R _   -> true
    W w   -> commutative w
    C _ _ -> false
    U     -> false


{- Type-driven combination -}

-- A semantic derivation is a proof that a particular string has a
-- particular meaning at a particular type
-- For displaying derivations, we also maintain the subproofs used at
-- each proof step
data Proof = Proof String Sem Ty (List Proof)
derive instance Eq Proof
derive instance Generic Proof _
instance Show Proof where
  show t = genericShow t

getProofType :: Proof -> Ty
getProofType (Proof _ _ ty _) = ty

-- Evaluate a constituency tree by finding all the derivations of its
-- daughters and then all the ways of combining those derivations in accordance
-- with their types and the available modes of combination
synsem :: Syn -> List Proof
synsem = execute <<< go
  where
    go (Leaf s d t)   = pure $ singleton $ Proof s (Lex d) t Nil
    go (Branch l r) = do -- memo block
      lefts  <- go l
      rights <- go r
      map concat $ sequence do -- list block
        lp@(Proof lstr lval lty _) <- lefts
        rp@(Proof rstr rval rty _) <- rights
        pure do -- memo block
          combos <- combine lty rty
          pure do -- list block
            (op ^ d ^ ty) <- combos
            -- traceM ("left: " <>  show (semTerm lval))
            -- traceM ("right: " <> show (semTerm rval))
            -- traceM ("op: " <> show op <> " = " <> show d)
            -- traceM ("result: " <> show_term (eval $ d % semTerm lval % semTerm rval))
            let cval = Comb op (eval $ d % semTerm lval % semTerm rval)
            pure $ Proof (lstr <> " " <> rstr) cval ty (lp:rp:Nil)

prove ∷ CFG -> Lexicon -> String -> Maybe (List Proof)
prove cfg lex input = concatMap synsem <$> parse cfg lex input

-- The basic unEffectful modes of combination (add to these as you like)
modes :: Ty -> Ty -> List (Mode ^ Term ^ Ty)
modes = case _,_ of
  a :-> b , r       | a == r -> pure (pure FA ^ opTerm FA ^ b)
  l       , a :-> b | l == a -> pure (pure BA ^ opTerm BA ^ b)
  a :-> T , b :-> T | a == b -> pure (pure PM ^ opTerm PM ^ (a :-> T))
  _       , _                -> Nil

-- Make sure that two Effects can compatibly be sequenced
-- (only relevant to A and J modes)
combineFs :: F -> F -> List F
combineFs = case _,_ of
  S     , S                -> pure $ S
  R i   , R j    | i == j  -> pure $ R i
  W i   , W j    | i == j  -> pure $ W i
  C i j , C j' k | j == j' -> pure $ C i k
  _     , _                -> Nil

combine = curry $ fix (memoize' <<< openCombine)

-- Here is the essential type-driven combination logic; given two types,
-- what are all the ways that they may be combined
openCombine ::
  forall m. Monad m
  => ((Ty ^ Ty) -> m (List (Mode ^ Term ^ Ty)))
  ->  (Ty ^ Ty) -> m (List (Mode ^ Term ^ Ty))
openCombine combine (l ^ r) = {-map (\(m^d^t) -> (m ^ eval d ^ t)) <<< -}concat <$>

  -- for starters, try the basic modes of combination
  pure (modes l r)

  -- then if the left daughter is Functorial, try to find a mode
  -- `op` that would combine its underlying type with the right daughter
  <+> case l of
    Eff f a | functor f ->
      combine (a ^ r) <#>
      map \(op^d^c) -> (ML f:op ^ opTerm (ML f) % d ^ Eff f c)
    _ -> pure Nil

  -- vice versa if the right daughter is Functorial
  <+> case r of
    Eff f a | functor f ->
      combine (l ^ a) <#>
      map \(op^d^c) -> (MR f:op ^ opTerm (MR f) % d ^ Eff f c)
    _ -> pure Nil

  -- if the left daughter requests something Functorial, try to find an
  -- `op` that would combine it with a `pure`ified right daughter
  <+> case l of
    Eff f a :-> b | appl f ->
      combine (a :-> b ^ r) <#>
      concatMap \(op^d^c) -> let m = UR f
                              in guard (norm op m) *> pure (m:op ^ opTerm m % d ^ c)
    _ -> pure Nil

  -- vice versa if the right daughter requests something Functorial
  <+> case r of
    Eff f a :-> b | appl f ->
      combine (l ^ a :-> b) <#>
      concatMap \(op^d^c) -> let m = UL f
                              in guard (norm op m) *> pure (m:op ^ opTerm m % d ^ c)
    _ -> pure Nil

  -- additionally, if both daughters are Applicative, then see if there's
  -- some mode `op` that would combine their underlying types
  <+> case (l ^r) of
    (Eff f a ^ Eff g b) | appl f ->
      combine (a ^ b) <#>
      lift2 (\h (op^d^c) -> let m = A h
                             in (m:op ^ opTerm m % d ^ Eff h c)) (combineFs f g)
    _ -> pure Nil

  -- if the left daughter is left adjoint to the right daughter, cancel them out
  -- and fina a mode `op` that will combine their underlying types
  -- note that the asymmetry of adjunction rules out xover
  -- there remains some derivational ambiguity:
  -- W,W,R,R has 3 all-cancelling derivations not 2 due to local WR/RW ambig
  <+> case (l ^r) of
    (Eff f a ^ Eff g b) | adjoint f g ->
      combine (a ^ b) <#>
      concatMap \(op^d^c) -> do (m^eff) <- (Eps ^ identity) : (XL f Eps ^ Eff f) : Nil
                                pure (m:op ^ opTerm m % d ^ eff c)
    _ -> pure Nil

  -- finally see if the resulting types can additionally be lowered (D),
  -- joined (J)
  <**> pure (addD : {-addEps :-} addJ : pure : Nil)

addJ :: (Mode ^ Term ^ Ty) -> List (Mode ^ Term ^ Ty)
addJ = case _ of
  (op ^ d ^ Eff f (Eff g a)) | monad f, norm op (J f) ->
    combineFs f g <#> \h -> (J h:op ^ opTerm (J h) % d ^ Eff h a)
  _ -> Nil

addD :: (Mode ^ Term ^ Ty) -> List (Mode ^ Term ^ Ty)
addD = case _ of
  (op ^ d ^ Eff (C i a) a') | a == a', norm op D ->
    pure (D:op ^ opTerm D % d ^ i)
  _ -> Nil

norm :: Mode -> Op -> Boolean
norm op = case _ of
  UR f -> not $ (op `startsWith`_) `anyOf` [[MR f], [D, MR f]]
  UL f -> not $ (op `startsWith`_) `anyOf` [[ML f], [D, ML f]]
  D    -> not $ (op `startsWith`_) `anyOf`
    (map (\m -> [m  U, D, m  U]) [MR, ML]
           <> [ [ML U, D, MR U]
              , [A  U, D, MR U]
              , [ML U, D, A  U]
              , [Eps]
              ])
  J f -> not $ (op `startsWith` _) `anyOf`
    -- avoid higher-order detours for all J-able effects
    (lift2 (\k m -> [m  f] <> k <> [m  f]) [[J f], []] [MR, ML]
    <> map (\k -> [ML f] <> k <> [MR f])  [[J f], []]
    <> map (\k -> [A  f] <> k <> [MR f])  [[J f], []]
    <> map (\k -> [ML f] <> k <> [A  f])  [[J f], []]
    <> map (\k ->           k <> [Eps] )  [{-[A f],-} []] -- safe if no lexical FRFs
    -- and all (non-split) inverse scope for commutative effects
    <> if commutative f
          then    [ [MR f, A  f] ]
               <> [ [A  f, ML f] ]
               <> map (\k -> [MR f] <> k <> [ML f]) [[J f], []]
               <> map (\k -> [A  f] <> k <> [A  f]) [[J f], []]
          else [])
  _ -> true

  where
    startsWith Nil _         = false
    startsWith _  Nil        = true
    startsWith (x:xs) (y:ys) = x == y && startsWith xs ys
    anyOf p as = any p (map fromFoldable as)

sweepSpurious :: List (Mode ^ Term ^ Ty) -> List (Mode ^ Term ^ Ty)
sweepSpurious ops = foldr filter ops
  [
  -- -- EXPERIMENTAL: W's only take surface scope over W's
  -- , \(m ^ _) -> not $ any (m `contains 1` _) $

  --        ( (ML (W E): A (W E): Eps: Nil) <#> \m -> MR (W E) (m FA) )

  -- -- EXPERIMENTAL: drefs float up
  -- , \(m ^ _) -> not $ any (m `contains 1` _) $

  --        ( scopetakers >>= \f -> (ML f (MR (W E) FA) : MR f (ML (W E) FA) : Nil) )
  ]
  -- where
  --   contains n haystack needle = DS.contains (DS.Pattern $ modeAsList n needle) $ modeAsList n haystack
  --   commuter = filter commutative atomicEffects
  --   scopetakers = atomicEffects >>= case _ of
  --     W _ -> Nil
  --     R _ -> Nil
  --     x   -> pure x


{- Mapping semantic values to (un-normalized) Lambda_calc terms -}

semTerm :: Sem -> Term
semTerm (Lex w)    = w
semTerm (Comb m d) = d

-- The definitions of the combinators that build our modes of combination
-- Here we are using the Lambda_calc library to write (untyped) lambda expressions
-- that we can display in various forms
opTerm :: Op -> Term
opTerm = case _ of
          -- \l r -> l r
  FA      -> l ! r ! l % r

          -- \l r -> r l
  BA      -> l ! r ! r % l

          -- \l r a -> l a `and` r a
  PM      -> l ! r ! a ! make_var "and" % (l % a) % (r % a)

          -- \l r a -> l (r a)
  FC      -> l ! r ! a ! l % (r % a)

          -- \l R -> (\a -> op l a) <$> R
  MR f -> op ! l ! r ! fmapTerm f % (a ! (op % l % a)) % r

       --    \L r -> (\a -> op a r) <$> L
  ML f -> op ! l ! r ! fmapTerm f % (a ! (op % a % r)) % l

       --    \l R -> op (\a -> R (pure a)) l
  UL f -> op ! l ! r ! op % (a ! r % (pureTerm f % a)) % l

       --    \L r -> op (\a -> L (pure a)) r
  UR f -> op ! l ! r ! op % (a ! l % (pureTerm f % a)) % r

       --    \L R -> op <$> L <*> R
  A  f -> op ! l ! r ! joinTerm f % (fmapTerm f % (a ! fmapTerm f % (op % a) % r) % l)

       --    \l r a -> op l (r a) a
  -- Z    op ! -> l ! r ! a ! modeTerm op % l % (r % a) % a

       --    \l r -> join (op l r)
  J  f -> op ! l ! r ! joinTerm f % (op % l % r)

          -- \l r -> counit $ (\a -> op a <$> r) <$> l
  Eps  -> op ! l ! r ! counitTerm % (fmapTerm (W E) % (a ! fmapTerm (R E) % (op % a) % r) % l)

          -- \l r -> op l r id
  D    -> op ! l ! r ! op % l % r % (a ! a)

  XL f o -> op ! l ! r ! extendTerm f % (l' ! opTerm o % op % l' % r) % l

l = make_var "l"
l' = make_var "l'"
r = make_var "r"
a = make_var "a"
b = make_var "b"
g = make_var "g"
k = make_var "k"
m = make_var "m"
p = make_var "p"
mm = make_var "mm"
c = make_var "c"
op = make_var "op"

fmapTerm = case _ of
  S     -> k ! m ! set ( (a ! k % (get_rng m % a)) |? get_dom m )
  R _   -> k ! m ! g ! k % (m % g)
  W _   -> k ! m ! _1 m * k % _2 m
  C _ _ -> k ! m ! c ! m % (a ! c % (k % a))
  _     -> k ! m ! make_var "fmap" % k % m
pureTerm = case _ of
  S     -> a ! make_set a
  R _   -> a ! g ! a
  W t   -> a ! (mzeroTerm t * a)
  C _ _ -> a ! k ! k % a
  _     -> a ! make_var "pure" % a
counitTerm = m ! _2 m % _1 m
joinTerm = case _ of
  -- S     -> mm ! set ( (p ! get_rng (get_rng mm % (_1 p)) % (_2 p)) |? (get_dom mm * (a ! get_dom (get_rng mm % a))) )
  S     -> mm ! conc mm
  R _   -> mm ! g ! mm % g % g
  W t   -> mm ! (_1 mm) `mplusTerm t` (_1 (_1 mm)) * _2 (_2 mm)
  C _ _ -> mm ! c ! mm % (m ! m % c)
  _     -> mm ! make_var "join" % mm
extendTerm = case _ of
  W t   -> k ! m ! _1 m * k % m
  _     -> make_var "co-tastrophe"
mzeroTerm = case _ of
  T     -> make_var "true"
  _     -> make_var "this really shouldn't happen"
mplusTerm = case _ of
  T     -> \p q -> make_var "and" % p % q
  _     -> \_ _ -> make_var "this really shouldn't happen"

{-- some test terms -}
left = (Lex (Set (App (Var (VC 0 "some")) (Var (VC 0 "person"))) (Lam (VC 0 "x") (Var (VC 0 "x")))))
right = (Comb (A S : BA : Nil) (Set (Pair (Dom (App (Var (VC 0 "some")) (Var (VC 0 "cat")))) (Lam (VC 0 "s") (Dom (App (Var (VC 0 "some")) (Var (VC 0 "dog")))))) (Lam (VC 0 "p") (App (App (Var (VC 0 "gave")) (App (Rng (App (Var (VC 0 "some")) (Var (VC 0 "cat")))) (Fst (Spl 1 (Var (VC 0 "p")))))) (App (Rng (App (Var (VC 0 "some")) (Var (VC 0 "dog")))) (Snd (Spl 1 (Var (VC 0 "p")))))))))
res = eval $ opTerm (A S) % opTerm BA % semTerm left % semTerm right