module Text.Shaun.Lexer
  ( makeLexer
  , Token(..)
  , Atom(..)
  )
where

import Text.Shaun.Types

import Text.Parsec
import Text.Parsec.Char
import Text.Parsec.ByteString

import Data.ByteString (ByteString(..))
import Prelude hiding (readFile)

import Control.Monad.Catch (throwM)

-- | The output data structure of the lexer.
data Token
  = TKey String
  | TId String
  | TAtom Atom
  | TComment String
  deriving (Show)

-- | Shaun's Atomic values are wrapped in this data structure to
-- make use of the @Shaun@ type class in the parser.
data Atom
  = AString String
  | ABool Bool
  | ADouble Double
  | ANull
  deriving (Show)

instance Shaun Atom where
  toShaun (AString s) = SString s
  toShaun (ABool b) = SBool b
  toShaun (ADouble d) = SNumber d Nothing
  toShaun ANull = SNull

  fromShaun (SString s) = return $ AString s
  fromShaun (SBool b) = return $ ABool b
  fromShaun (SNumber d _) = return $ ADouble d
  fromShaun SNull = return ANull
  fromShaun _ = throwM $ Custom "Can't convert Shaun to Atom"

kwds = [ "{", "}", "[", "]", ":" ]

-- | @ComType@ defines a comment type. @One s@ defines a one-line comment
-- while @Multi l r@ defines a multi-line comment.
data ComType = One String | Multi String String

comTypes = [ Multi "/*" "*/", Multi "(" ")", One "//" ]

-- | @makeLexer bs@ translates a @ByteString@ SHAUN text into a list of tokens.
makeLexer :: ByteString -> Either ParseError [Token]
makeLexer = parse lexP ""
  where
    lexP :: Parser [Token]
    lexP = ws >> (sepEndBy (keyP <|> try atomP <|> idP <|> commentP) ws)

    keyP :: Parser Token
    keyP     = fmap TKey $ choice (map string kwds)

    idP :: Parser Token
    idP      = fmap TId  $ do
      f <- letter <|> char '_'
      n <- many (alphaNum <|> char '_')
      return (f:n)

    atomP :: Parser Token
    atomP    = fmap TAtom $ strP <|> boolP <|> numberP
      where 
        strP :: Parser Atom
        strP = fmap AString $ do
          c <- fmap sourceColumn getPosition

          s <- between
                (char '"')
                (char '"')
                (many $ specialChar <|> noneOf "\"")
          format c s
          where
            format :: Column -> String -> Parser String
            format c s = case lines s of
	      []  -> return ""
              [l] -> return l

              -- multiline with an empty first line
              ("":l1:rest) -> do
                let nc = min c $ length (takeWhile (==' ') l1)
                let new_rest = map (\s -> let (sp, r) = span (==' ') s in
                                            if length sp > nc then
                                              snd $ splitAt nc s
                                            else r)
                                    (l1:rest)

                return $ init $ unlines new_rest

              -- multiline without empty first line
              (l1:rest)  -> do
                let new_rest = map (\s -> let (sp, r) = span (==' ') s in
                                            if length sp > c then
                                              snd $ splitAt c s
                                            else r)
                                    (l1:rest)
                return $ init $ unlines new_rest




        -- handles escaped char
        specialChar :: Parser Char
        specialChar = do
          char '\\'
          anyChar >>= convert

          where convert '\\' = return '\\'
                convert 'n'  = return '\n'
                convert 'r'  = return '\r'
                convert 't'  = return '\t'
                convert '"'  = return '"'
                convert c = parserFail ("Illegal escaped char '"++[c]++"'")

        boolP :: Parser Atom
        boolP = (string "true" >> return (ABool True))
            <|> (string "false" >> return (ABool False))

        numberP :: Parser Atom
        numberP = do
          s <- option "" (fmap (:"") $ oneOf "-+")
          i <- many1 digit
          d <- option "0" (char '.' >> many1 digit)
          e <- option "" $ do
                 oneOf "eE"
                 s <- option '+' (oneOf "-+")
                 coef <- many1 digit 
                 return ("e"++[s]++coef)

          return (ADouble (read (s++i++"."++d++e)))

        nullP :: Parser Atom
        nullP = (string "null" >> return ANull)

    commentP :: Parser Token
    commentP = fmap TComment $ choice $ map (try . toComP) comTypes
      where
        toComP :: ComType -> Parser String
        toComP (Multi l r) = do
          string l
          mid <- manyTill anyChar (string r)
          return (l++mid++r)
        toComP (One b) = do
          string b
          manyTill anyChar endOfLine >>= return . (b++)




    ws :: Parser ()
    ws  = skipMany ws1

    ws1 :: Parser Char
    ws1 = space <|> char ','
