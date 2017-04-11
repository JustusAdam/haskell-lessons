#!/usr/bin/env stack runhaskell -- 

import System.Directory hiding (doesDirectoryExist, getDirectoryContents)
import System.FilePath
import Control.Monad.Extra
import Development.Shake
import System.IO
import Data.Foldable

outputDirectory :: FilePath
outputDirectory = "docs"

scriptOutputDirectory :: FilePath
scriptOutputDirectory = outputDirectory </> "script"

slidesOutputDirectory :: FilePath
slidesOutputDirectory = outputDirectory </>  "slides"

revealResourcesDirectory :: FilePath
revealResourcesDirectory = slidesOutputDirectory </> "reveal.js"

copyFromReveal :: FilePath -> Action ()
copyFromReveal out = 
    let originalFile = joinPath $ dropWhile (/= "reveal.js/") $ splitPath $ slidesOutputDirectory `makeRelative` out
    in do 
        need [originalFile]
        liftIO $ copyFile originalFile out

needRstSources :: Action ()
needRstSources = getDirectoryFiles "script/source" ["*.rst", "exercises/*.rst"] >>= need . map ("script/source" </>)

buildSlideWithTheme :: String -> FilePath -> Action ()
buildSlideWithTheme theme out = do
    let sourceFile = "slides" </> takeFileName out -<.> ".md"
        templateFile = "slides/template.html"
    need [sourceFile, templateFile]
    -- getDirectoryFiles "slides/img" ["*.png"] >>= need . map ((slidesOutputDirectory </> "img") </>)
    cmd "pandoc" [sourceFile, "--slide-level", "2", "-o", out, "-t", "revealjs", "-s", "--variable=theme:" ++ theme, "--template", templateFile]

main :: IO ()
main = shakeArgs shakeOptions $ do
    want ["script", "slides", outputDirectory </> ".nojekyll"]

    phony "script" $ need [scriptOutputDirectory </> "index.html", outputDirectory </> "script.pdf"]

    phony "slides" $ do 
        slideMds <- getDirectoryFiles "slides" ["*.md"]
        let htmls = map (-<.> "html") slideMds
        need $ map (slidesOutputDirectory </>) $ htmls ++ map ("white" </>) htmls

    phony "clean" $ do 
        removeFilesAfter outputDirectory ["*.html"]
        liftIO $ removeDirectoryRecursive scriptOutputDirectory
        mapM_ (liftIO . removeDirectoryRecursive) . filter (/= "reveal.js") =<< filterM doesDirectoryExist =<< getDirectoryContents slidesOutputDirectory
        mapM_ (liftIO . removeDirectoryRecursive) =<< filterM doesDirectoryExist [scriptOutputDirectory, slidesOutputDirectory]

    "**/.nojekyll" %> \out -> liftIO $ withFile out AppendMode (`hPutChar` ' ')

    (scriptOutputDirectory </> "index.html") %> \out' -> do
        let out = takeDirectory out'
        needRstSources
        unit $ cmd "make" ["html"] (Cwd "script")
        liftIO $ removeDirectoryRecursive out
        liftIO $ renameDirectory "script/build/html" out

    (outputDirectory </> "script.pdf") %> \out -> do
        needRstSources
        unit $ cmd "make" ["latexpdf"] (Cwd "script")
        liftIO $ renameFile "script/build/latex/HaskellLessons.pdf" out

    (slidesOutputDirectory </> "img" </> "*") %> liftIO . (copyFile <$> ("slides/img" </>) . takeFileName <*> id)

    (slidesOutputDirectory </> "*.html") %> buildSlideWithTheme "black"
    (slidesOutputDirectory </> "*/*.html") %> \out -> 
        let theme = takeBaseName $ takeDirectory $ makeRelative slidesOutputDirectory out
        in buildSlideWithTheme theme out
