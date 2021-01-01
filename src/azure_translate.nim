import httpclient, tables, json, options, strutils, uri
import nuuid

const 
    api_base = parseUri("https://api.cognitive.microsofttranslator.com/")
    api_version = @{"api-version": "3.0"}  # Azure Translate API Version

type
    AzureTranslateError* = object of CatchableError
        ## Raised when the API returns an error. See `msg` as well
        code*: int
    TextQuery = openArray[string]
    DictExQuery* = tuple[text, translation: string]  ## Type alias for `dictionay_example` endpoint parameter
    Scope* = enum
        ## Scope for `languages` endpoint
        azTranslation, azTransliteration, azDictionary
    TextType* {.pure.} = enum
        ## for `translate` endpoint
        plain, html
    ProfanityAction* {.pure.} = enum
        ## for `translate` endpoint
        noAction, marked, deleted
    ProfanityMarker* {.pure.} = enum
        ## for `translate` endpoint
        asterisk, tag

    # Sub-objects
    BaseLanguage* = object of RootObj
        name*, nativeName*: string

    ScriptLanguage* = object
        code*, name*, nativeName*, dir*: string
        toScripts*: Option[seq[ScriptLanguage]]

    TranslationLanguage* = object of BaseLanguage
        dir*: string

    TransliterationLanguage* = object of BaseLanguage
        scripts*: seq[ScriptLanguage]

    DictionaryTranslation* = object
        name*, nativeName*, dir*, code*: string

    DictionaryLanguage* = object
        dir*, name*, nativeName*: string
        translations*: seq[DictionaryTranslation]

    Alignment* = object 
        proj*: string

    SentenceBoundaries* = object
        srcSentLen*, transSentLen*: seq[Natural]
    
    SourceText* = object
        text*: string

    BaseTranslation* = object
        to*, text*: string
        transliteration*: Option[Transliteration]
        alignment*: Option[Alignment]
        sentLen*: Option[SentenceBoundaries]
        sourceText*: Option[SourceText]
    
    DetectedLanguage* = object of RootObj
        language*: string
        score*: range[0.0..1.0]

    BackTranslations* = object
        normalizedText, displayText: string
        numExamples, frequencyCount: Natural

    DictionaryLookupTranslations* = object
        normalizedTarget*, displayTarget*, posTag*, prefixWord*: string
        confidence*: range[0.0..1.0]
        backTranslations*: seq[BackTranslations]
    
    BaseDictionaryExample* = object
        sourcePrefix, sourceTerm, sourceSuffix, targetPrefix, targetTerm, targetSuffix: string

    # API Result objects
    Languages* = object
        translation*: Option[Table[string, TranslationLanguage]]
        transliteration*: Option[Table[string, TransliterationLanguage]]
        dictionary*: Option[Table[string, DictionaryLanguage]]

    Translation* = object 
        detectedLanguage*: Option[DetectedLanguage]  ## Exists only when `from` is omited in `translate` endpoint
        translations*: seq[BaseTranslation]

    Transliteration* = object
        script*, text*: string

    Detection* = object of DetectedLanguage
        isTranslationSupported*, isTransliterationSupported*: bool
        alternatives*: Option[seq[Detection]]
    
    BreakSentence* = object
        sentLen*: seq[Natural]
        detectedLanguage*: Option[DetectedLanguage]

    DictionaryLookup* = object
        normalizedSource*, displaySource*: string
        translations*: seq[DictionaryLookupTranslations]

    DictionaryExample* = object
        normalizedSource*, normalizedTarget*: string
        examples*: seq[BaseDictionaryExample]

proc `$`(s: Scope): string =
    system.`$`(s)[2 .. ^1].toLowerAscii
proc `$`(p: ProfanityAction | ProfanityMarker): string =
    system.`$`(p).capitalizeAscii

proc toSeq[T](jnode: JsonNode): seq[T] =
  if jnode.kind == Jarray:
    for n in jnode:
      result.add(to(n, T))

proc toJArray(text: openArray[string]): JsonNode =
    result = JsonNode(kind: JArray, elems: @[])
    for t in text:
        result.add(JsonNode(kind: JObject, fields: {"Text": %t}.toOrderedTable))

let client = newHttpClient()

proc endpoint(`method`: string, query: seq[(string, string)]): string =
    $(api_base / `method` ? api_version & query)

proc endpoint(`method`: string): string = 
    endpoint(`method`, newSeq[(string, string)]())

proc newHeaders(key: string): HttpHeaders =
    # Generate a new set of headers for each request
    new result
    result.table = {
        "Ocp-Apim-Subscription-Key": @[key],
        "Content-type": @["application/json"],
        "X-ClientTraceId": @[$generateUUID()]
    }.newTable

proc request(uri, key, body: string): Response =
    result = client.request(uri, httpMethod = HttpPost, headers = newHeaders(key), body = body)

    if result.code.is4xx:
        let json = parseJson(result.body)
        if json.hasKey("error"):
            raise (ref AzureTranslateError)(code: json["error"]["code"].getInt, msg: json["error"]["message"].getStr)
        else:
            raise (ref AzureTranslateError)(msg: result.body)


proc languages*(key: string, scope: openArray[Scope] = [], acceptLanguage: Option[string] = none(string)): Languages =
    ## Gets the set of languages currently supported by other operations of the Translator.
    var headers = newHeaders(key)
    if acceptLanguage.isSome:
        headers["Accept-Language"] = acceptLanguage.get

    var uri = endpoint("languages")
    if scope.len > 0:
        uri &= "&scope=" & scope.join(",")
    
    let resp = client.request(uri, httpMethod = HttpGet, headers = newHeaders(key))
    var respJson = parseJson(resp.body)

    result = to(respJson, Languages)

proc translate*(key: string, text: TextQuery, to: openArray[string], `from`: Option[string] = none(string), 
    textType: Option[TextType] = none(TextType), category: Option[string] = none(string), 
    profanityAction: Option[ProfanityAction] = none(ProfanityAction), profanityMarker: Option[ProfanityMarker] = none(ProfanityMarker),
    includeAlignment, includeSentenceLength: Option[bool] = none(bool),
    suggestedFrom, fromScript, toScript: Option[string] = none(string),
    allowFallback: Option[bool] = none(bool)): seq[Translation] = 
    ## Translates text.
    ## Note that using category has not been tested

    var query = newSeq[(string, string)]()
    for t in to:
        query.add({"to": t})
    if `from`.isSome:
        query.add({"from": `from`.get})
    if textType.isSome:
        query.add({"textType": $textType.get})
    if category.isSome:
        query.add({"category": category.get})
    if profanityAction.isSome:
        query.add({"profanityAction": $profanityAction.get})
    if profanityMarker.isSome:
        query.add({"profanityMarker": $profanityMarker.get})
    if includeAlignment.isSome:
        query.add({"includeAlignment": $includeAlignment.get})
    if includeSentenceLength.isSome:
        query.add({"includeSentenceLength": $includeSentenceLength.get})
    if suggestedFrom.isSome:
        query.add({"suggestedFrom": suggestedFrom.get})
    if fromScript.isSome:
        query.add({"fromScript": fromScript.get})
    if toScript.isSome:
        query.add({"toScript": toScript.get})
    if allowFallback.isSome:
        query.add({"allowFallback": $allowFallback.get})

    let 
        resp = request(endpoint("translate", query), key, $text.toJArray)
        respJson = parseJson(resp.body)
    
    result = toSeq[Translation](respJson)


proc transliterate*(key: string, text: TextQuery, language, fromScript, toScript: string): seq[Transliteration] =
    ## Converts text in one language from one script to another script.
    let 
        query = @{"language": language, "fromScript": fromScript, "toScript": toScript}
        resp = request(endpoint("transliterate", query), key, $text.toJArray)
        respJson = parseJson(resp.body)

    result = toSeq[Transliteration](respJson)


proc detect*(key: string, text: TextQuery): seq[Detection] =
    ## Identifies the language of a piece of text
    let 
        resp = request(endpoint("detect"), key, $text.toJArray)
        respJson = parseJson(resp.body)

    result = toSeq[Detection](respJson)


proc break_sentence*(key: string, text: TextQuery, language, script: Option[string] = none(string)): seq[BreakSentence] = 
    ## Identifies the positioning of sentence boundaries in a piece of text

    var uri = endpoint("breaksentence")
    if language.isSome:
        uri &= "&language=" & language.get
    if script.isSome:
        uri &= "&script=" & script.get

    let 
        resp = request(uri, key, $text.toJArray)
        respJson = parseJson(resp.body)

    result = toSeq[BreakSentence](respJson)
    

proc dictionary_lookup*(key: string, text: TextQuery, `from`, to: string): seq[DictionaryLookup] =
    ## Provides alternative translations for a word and a small number of idiomatic phrases. 
    ## Each translation has a part-of-speech and a list of back-translations. 
    ## The back-translations enable a user to understand the translation in context. 
    ## The Dictionary Example operation allows further drill down to see example uses of each translation pair.
    let 
        uri = endpoint("dictionary/lookup", @{"from": `from`, "to": to})
        resp = request(uri, key, $text.toJArray)
        respJson = parseJson(resp.body)

    result = toSeq[DictionaryLookup](respJson)


proc dictionary_examples*(key: string, query: openArray[DictExQuery], `from`, to: string): seq[DictionaryExample] =
    ## Provides examples that show how terms in the dictionary are used in context. 
    ## This operation is used in tandem with Dictionary lookup.
    
    var body = JsonNode(kind: JArray, elems: @[])
    for t in query:
        body.add(JsonNode(kind: JObject, fields: {"Text": %t.text, "Translation": %t.translation}.toOrderedTable))

    let 
        uri = endpoint("dictionary/examples", @{"from": `from`, "to": to})
        resp = request(uri, key, $body)
        respJson = parseJson(resp.body)

    result = toSeq[DictionaryExample](respJson)
