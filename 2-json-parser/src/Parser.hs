module Parser where

import Tokenizer
import System.Environment (getArgs)
import System.Directory (doesFileExist)
import System.Exit
import System.IO
import Control.Monad

deepRecursionLimit :: Int
deepRecursionLimit = 20

data StringValueExpression = StringValueExpression { getStringValue :: String } deriving (Show, Eq)
data Expression =  NullExpression 
        | BooleanExpression { getBooleanValue :: Bool }
        | NumberExpression { getNumberValue :: Float }
        | StringExpression StringValueExpression 
        | ArrayExpression { getArrayElements :: [Expression] }
        | ObjectExpression { getFields :: [(StringValueExpression, Expression)] }
    deriving (Show, Eq)

removeLeadingAndTrailingSymbols::String -> String
removeLeadingAndTrailingSymbols s = case s of 
    [] -> []
    (_: xs) -> init xs

parseArrayElements :: Int -> Tokenizer -> Either String ([Expression], Tokenizer) 
parseArrayElements currentRecursionLevel tokenizer = do 
    when (currentRecursionLevel == 0) $ Left "too deep recursion"
    t <- eat Whitespace tokenizer
    case lookahead t of 
        Just CloseSquareBracket -> return ([], t)
        Just _ -> do 
            (value, t2) <- parseExpression currentRecursionLevel t
            case lookahead t2 of 
                Just Comma -> do  
                            (values, t4) <- eat Comma t2 >>= parseArrayElements currentRecursionLevel
                            if null values then
                                Left "expected array values after , symbol"
                            else 
                                return ((value: values), t4)
                Just _ -> return ([value], t2)
                Nothing -> Left "there are no tokens!"
        Nothing -> Left "there are no tokens!"

parseArrayExpression :: Int -> Tokenizer -> Either String (Expression, Tokenizer) 
parseArrayExpression currentRecursionLevel tokenizer = do
    when (currentRecursionLevel == 0) $ Left "too deep recursion"
    t <- eat OpenSquareBracket tokenizer >>= eat Whitespace
    case lookahead t of 
        Just CloseBracket -> do 
            t2 <- eat CloseSquareBracket t
            return (ArrayExpression { getArrayElements = [] }, t2) 
        Just _ -> do 
            (elements, t2) <- parseArrayElements (currentRecursionLevel - 1) t
            t3 <- eat CloseSquareBracket t2
            return (ArrayExpression { getArrayElements = elements}, t3)
        Nothing -> Left "expected close square bracket"

parsePrimitiveExpression :: Tokenizer -> Either String (Expression, Tokenizer) 
parsePrimitiveExpression tokenizer = do 
    (expression, t) <- case getNextToken tokenizer of 
        Just(Token {getTokenType = NumberType, getTokenValue = value }, t) -> 
            return (NumberExpression { getNumberValue = read(value) }, t)
        Just(Token {getTokenType = StringType, getTokenValue = value }, t) -> 
            return (StringExpression $ StringValueExpression { getStringValue = removeLeadingAndTrailingSymbols value }, t)
        Just(Token {getTokenType = NullType }, t) -> 
            return (NullExpression, t)
        Just(Token {getTokenType = BooleanType, getTokenValue = value }, t) -> 
            return (BooleanExpression { getBooleanValue = value == "true" }, t)
        Just(Token {getTokenType = t}, _) -> Left $ "other types of values are not supported: " ++ show(t)
        Nothing -> Left "there are no tokens but expected at least one"
    tk <- eat Whitespace t
    return (expression, tk)

parseExpression :: Int -> Tokenizer -> Either String (Expression, Tokenizer)
parseExpression currentRecursionLevel tokenizer = do 
    case lookahead tokenizer of
        Just OpenBracket -> parseObjectExpression currentRecursionLevel tokenizer
        Just OpenSquareBracket -> parseArrayExpression currentRecursionLevel tokenizer
        _ -> parsePrimitiveExpression tokenizer

parseFieldExpression :: Int -> Tokenizer -> Either String ((StringValueExpression, Expression), Tokenizer) 
parseFieldExpression currentRecursionLevel tokenizer = do 
    t1 <- eat Whitespace tokenizer
    (key, t2) <- case lookahead t1 of 
        Just StringType -> case getNextToken t1 of 
                Just (Token { getTokenType = StringType, getTokenValue = v }, tk) ->
                    return (StringValueExpression { getStringValue = removeLeadingAndTrailingSymbols v }, tk)
                Just x -> Left $ "expected string token, but " ++ show(x) ++ " token found"
                Nothing -> Left "there are no tokens!"
        Just x -> Left $ "expected string token, but " ++ show(x) ++ " found"
        Nothing -> Left "expected string token, there are no tokens!"
    t3 <- eat Whitespace t2 >>= eat Colon >>= eat Whitespace 
    (value, t4) <- parseExpression currentRecursionLevel t3
    t5 <- eat Whitespace t4
    return ((key, value), t5)

parseFieldExpressions :: Int -> Tokenizer -> Either String ([(StringValueExpression, Expression)], Tokenizer)
parseFieldExpressions currentRecursionLevel tokenizer = do 
    when (currentRecursionLevel == 0) $ Left "too deep recursion"
    t1 <- eat Whitespace tokenizer
    case lookahead t1 of 
        Just CloseBracket -> return ([], t1)
        Just StringType -> do 
            (field, t2) <- parseFieldExpression currentRecursionLevel t1
            case lookahead t2 of 
                Just Comma -> do 
                    t3 <- eat Comma t2
                    (fields, t4) <- parseFieldExpressions currentRecursionLevel t3
                    if null fields then
                        Left "after , must be object field, but there is nothing"
                    else 
                        return ((field: fields), t4)
                Just _ -> return ([field], t2)
                Nothing ->  Left "there are no tokens!"
        Just x -> Left $ "expected string token, but " ++ show(x) ++ " found"
        Nothing -> Left "expected } token or string token, but there are no more tokens"

parseObjectExpression :: Int -> Tokenizer -> Either String (Expression, Tokenizer)
parseObjectExpression _ [] = Left "there no tokens for json object" 
parseObjectExpression currentRecursionLevel tokenizer = do 
    when (currentRecursionLevel == 0) $ Left "too deep recursion"
    t1 <- eat Whitespace tokenizer >>= eat OpenBracket >>= eat Whitespace
    case lookahead t1 of 
        Just CloseBracket -> do 
            t2 <- eat CloseBracket t1
            return (ObjectExpression { getFields = [] }, t2)
        Just StringType -> do 
            (fields, t) <- parseFieldExpressions (currentRecursionLevel - 1) t1
            t2 <- eat CloseBracket t
            return (ObjectExpression { getFields = fields }, t2)
        Just x -> Left $ "expected string token, but " ++ show(x) ++ " found"
        Nothing -> Left "expected } token or string token, but there are no more tokens"

getObjectExpression :: Tokenizer -> Either String Expression
getObjectExpression tokenizer = do
    t1 <- eat Whitespace tokenizer
    case lookahead t1 of 
        Just OpenBracket -> do
            (e, t2) <- parseObjectExpression deepRecursionLimit tokenizer
            t3 <- eat Whitespace t2
            case getNextToken t3 of 
                Nothing -> return e
                _ -> Left $ "there are more tokens than expected: " ++ show(t3)
        Just OpenSquareBracket -> do
            (e, t2) <- parseArrayExpression deepRecursionLimit tokenizer
            t3 <- eat Whitespace t2
            case getNextToken t3 of 
                Nothing -> return e
                _ -> Left $ "there are more tokens than expected: " ++ show(t3)
        Just x -> Left $ "expected { or [ tokens, but not " ++ show (x)
        Nothing -> Left "empty string"

readFileFrom :: FilePath -> IO String
readFileFrom filePath = do
    fileExists <- doesFileExist filePath
    if fileExists then 
        readFile filePath
    else 
        exitWithMessage $ "can't read the file: " ++ filePath

validateJson :: String -> Either String Bool
validateJson jsonStr = do 
    tk <- createTokenizer jsonStr
    _ <- getObjectExpression tk
    return True

exitWithMessage :: String -> IO a
exitWithMessage msg = hPutStrLn stderr msg >> exitWith (ExitFailure 2) 

main :: IO ()
main = do
    args <- getArgs
    case args of 
        [] -> exitWithMessage "expected parameter: path to json file"
        (filePath: _) -> do
            jsonStr <- readFileFrom filePath
            case validateJson jsonStr of 
                Left errorMsg -> exitWithMessage errorMsg
                _ -> return () 

