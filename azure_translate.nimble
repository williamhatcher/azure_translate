# Package

version       = "0.3.0"
author        = "William Hatcher"
description   = "Nim Library for Azure Cognitive Services Translate"
license       = "MIT"
srcDir        = "src"


# Dependencies
requires "nim >= 1.4.0"
requires "nuuid >= 0.1.0"

task genDoc, "Generates the documentation for azure_translate":
    rmDir("docs") # Clean old doc folder
    exec("nim doc2 --outdir=docs --project --index:on --git.url:https://github.com/williamhatcher/azure_translate --git.commit:master src/azure_translate.nim")
    exec("nim buildindex -o:docs/theindex.html docs/") # This builds the index to allow search to work

    writeFile("docs/index.html", """
    <!DOCTYPE html>
    <html>
      <head>
        <meta http-equiv="Refresh" content="0; url=azure_translate.html"/>
      </head>
      <body>
        <p>Click <a href="azure_translate.html">this link</a> if this does not redirect you.</p>
      </body>
    </html>
    """)