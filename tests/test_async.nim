# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import unittest, options, os, tables, strutils, re, httpclient, asyncdispatch

import azure_translate

let 
    client = newAsyncHttpClient()
    key = getEnv("AZURE_SECRET_KEY")

test "async invalid key":
    expect AzureTranslateError:
        discard waitFor translate(client, "", @[""], @[""])

suite "async languages":
    let all = waitFor languages(client, key)

    test "async translation languages":
        check(all.translation.isSome)
        check(all.translation.get["en"] == TranslationLanguage(dir: "ltr", name: "English", nativeName: "English"))
    
    test "async dictionary languages":
        check(all.dictionary.isSome)
        check(all.dictionary.get.hasKey("en"))

    test "async transliteration languages":
        check(all.transliteration.isSome)
        check(all.transliteration.get.hasKey("ar"))
    
    test "async single language":
        ## Ensures that only one of the 3 language types are populated
        let single = waitFor languages(client, key, @[azDictionary])
        check(single.dictionary.isSome)
        check(single.dictionary.get.hasKey("en"))

        check(single.translation.isNone)
        check(single.transliteration.isNone)

    test "async multiple languages":
        ## Ensures that only two of the 3 language types are populated
        let multiple = waitFor languages(client, key, @[azTransliteration, azTranslation])
        check(multiple.dictionary.isNone)
        
        check(multiple.translation.isSome)
        check(all.translation.get["en"] == TranslationLanguage(dir: "ltr", name: "English", nativeName: "English"))
        check(multiple.transliteration.isSome)
        check(all.transliteration.get.hasKey("ar"))

suite "async translate":
    const en_text = @["Hello, what is your name?"]

    test "async single input":
        let translation = translate(client, key, en_text, to = @["zh-Hans"], `from` = some("en")).waitFor[0].translations[0]

        check(translation.to == "zh-Hans")
        check(not translation.text.isEmptyOrWhitespace)

    test "async single input auto-detection":
        let translation = translate(client, key, en_text, @["es"]).waitFor[0]
        check(translation.detectedLanguage.get.language == "en")
        check(translation.translations[0].to == "es")
        check(not translation.translations[0].text.isEmptyOrWhitespace)

    test "async transliteration":
        let translation = translate(client, key, en_text, @["zh-Hans"], toScript=some("Latn")).waitFor[0]

        check(translation.detectedLanguage.get.language == "en")
        check(translation.translations[0].to == "zh-Hans")
        check(not translation.translations[0].text.isEmptyOrWhitespace)

    test "async multiple inputs":
        let translations = waitFor translate(client, key, text = en_text & @["I am fine, thank you."], to = @["zh-Hans"], `from` = some("en"))

        let first = translations[0].translations[0]
        check(first.to == "zh-Hans")
        check(not first.text.isEmptyOrWhitespace)

        let second = translations[1].translations[0]
        check(second.to == "zh-Hans")
        check(not second.text.isEmptyOrWhitespace)

    test "async multiple languages":
        let translations = translate(client, key, en_text, to = @["zh-Hans", "de"], `from` = some("en")).waitFor[0].translations

        let zh_hans = translations[0]
        check(zh_hans.to == "zh-Hans")
        check(not zh_hans.text.isEmptyOrWhitespace)

        let de = translations[1]
        check(de.to == "de")
        check(not de.text.isEmptyOrWhitespace)

    test "async profanity":
        let asterisk = translate(client, key, @["This is a fucking good idea."], to = @["de"], `from` = some("en"), profanityAction=some(ProfanityAction.marked)).waitFor[0]
            .translations[0]
        
        check(asterisk.to == "de")
        check("***" in asterisk.text)

        let tag = translate(client, key, @["This is a fucking good idea."], to = @["de"], `from` = some("en"), profanityAction=some(ProfanityAction.marked), profanityMarker=some(ProfanityMarker.tag)).waitFor[0]
            .translations[0]

        check(tag.to == "de")
        check(contains(tag.text, re"<profanity>[\s\S]+</profanity>"))


    test "async notranslate":
        ## translate content with markup and decide what's translated
        const content_markup_text = @["""<div class="notranslate">This will not be translated.</div>
        <div>This will be translated. </div>"""]
        let translation = translate(client, key, content_markup_text, to = @["zh-Hans"], `from` = some("en"), textType = some(TextType.html)).waitFor[0]
            .translations[0]

        check(translation.to == "zh-Hans")
        check("<div class=\"notranslate\">This will not be translated.</div>" in translation.text)

    test "async alignment":
        let translation = translate(client, key, @["The answer lies in machine translation."], to = @["fr"], some("en"), includeAlignment=some(true)).waitFor[0]
            .translations[0]

        check(translation.to == "fr")
        check(translation.alignment.isSome)
        check(not translation.alignment.get.proj.isEmptyOrWhitespace)

    test "async sentence boundaries":
        const sentence_boundary_text = @["The answer lies in machine translation. The best machine translation technology cannot always provide translations tailored to a site or users like a human. Simply copy and paste a code snippet anywhere."]
        let translation = translate(client, key, sentence_boundary_text, to = @["fr"], some("en"), includeSentenceLength=some(true)).waitFor[0]
            .translations[0]
        
        check(translation.to == "fr")
        check(translation.sentLen.isSome)
        check(translation.sentLen.get.srcSentLen == @[Natural(40), 117, 46])
        check(translation.sentLEn.get.transSentLen.len == 3)    # Only checking length as the numbers could change

    test "async dynamic dictionary":
        const dynamic_dictionary_text = @["The word <mstrans:dictionary translation=\"wordomatic\">word or phrase</mstrans:dictionary> is a dictionary entry."]
        let translation = translate(client, key, dynamic_dictionary_text, @["de"], some("en")).waitFor[0]
            .translations[0]
        check(translation.to == "de")
        check("wordomatic" in translation.text)

test "async transliterate":
    let res = waitFor transliterate(client, key, @["こんにちは", "さようなら"], "ja", "Jpan", "Latn")
    check(res[0].script == "Latn" and not res[0].text.isEmptyOrWhitespace)
    check(res[1].script == "Latn" and not res[1].text.isEmptyOrWhitespace)

test "async detect":
    let res = waitFor detect(client, key, @["What language is this text written in?", "이 텍스트는 어떤 언어로 쓰여져 있습니까?"])
    check(res[0].language == "en")
    check(res[1].language == "ko")

test "async break setence":
    let res = waitFor break_sentence(client, key, @["How are you? I am fine. What did you do today?"], language=some("en"))
    check(res[0].sentLen == @[Natural(13), 11, 22])  # Compiler assumes int if Natural is missing

test "async dictionary lookup":
    let entry = dictionary_lookup(client, key, @["fly"], `from`="en", to="es").waitFor[0]  # Getting first! (may need to change in the future)
    check(entry.normalizedSource == "fly")
    check(entry.displaySource == "fly")
    check(entry.translations.len > 0)

test "async dictionary examples":
    let example = dictionary_examples(client, key, @[(text: "fly", translation: "volar")], `from`="en", to="es").waitFor[0]
    check(example.normalizedSource == "fly")
    check(example.normalizedTarget == "volar")
    check(example.examples.len > 0)
