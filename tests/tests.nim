# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import unittest, options, os

import azure_translate

let key = getEnv("AZURE_SECRET_KEY")

test "invalid key":
    expect AzureTranslateError:
        discard translate("", [""], [""])

test "get languages":
    echo languages(key)

test "translate":
    const en_text = ["Hello, what is your name?"]

    test "Translate a single input":
        echo translate(key, en_text, to = ["zh-Hans"], `from` = some("en"))

    test "Translate a single input with language auto-detection":
        echo translate(key, en_text, ["zh-Hans"])

    test "Translate with transliteration":
        echo translate(key, en_text, ["zh-Hans"], toScript=some("Latn"))

    test "Translate multiple pieces of text":
        echo translate(key, text = @en_text & @["I am fine, thank you."], to = ["zh-Hans"], `from` = some("en"))

    test "Translate to multiple languages":
        echo translate(key, en_text, to = ["zh-Hans", "de"], `from` = some("en"))

    test "Handle profanity":
        echo translate(key, ["This is a fucking good idea."], to = ["de"], `from` = some("en"), profanityAction=some(ProfanityAction.marked))
        echo translate(key, ["This is a fucking good idea."], to = ["de"], `from` = some("en"), profanityAction=some(ProfanityAction.marked), profanityMarker=some(ProfanityMarker.tag))

    test "Translate content with markup and decide what's translated":
        const content_markup_text = ["""<div class="notranslate">This will not be translated.</div>
        <div>This will be translated. </div>"""]
        echo translate(key, content_markup_text, to = ["zh-Hans"], `from` = some("en"), textType = some(TextType.html))

    test "Obtain alignment information":
        echo translate(key, ["The answer lies in machine translation."], ["fr"], some("en"), includeAlignment=some(true))

    test "Obtain sentence boundaries":
        const sentence_boundary_text = ["The answer lies in machine translation. The best machine translation technology cannot always provide translations tailored to a site or users like a human. Simply copy and paste a code snippet anywhere."]
        echo translate(key, sentence_boundary_text, ["fr"], some("en"), includeSentenceLength=some(true))

    test "Translate with dynamic dictionary":
        const dynamic_dictionary_text = ["The word <mstrans:dictionary translation=\"wordomatic\">word or phrase</mstrans:dictionary> is a dictionary entry."]
        echo translate(key, dynamic_dictionary_text, ["de"], some("en"))

test "transliterate":
    echo transliterate(key, ["こんにちは", "さようなら"], "ja", "Jpan", "Latn")

test "detect":
    echo detect(key, ["What language is this text written in?", "이 텍스트는 어떤 언어로 쓰여져 있습니까?"])

test "break setence":
    echo break_sentence(key, ["How are you? I am fine. What did you do today?"])

test "dictionary lookup":
    echo dictionary_lookup(key, ["fly"], `from`="en", to="es")

test "dictionary examples":
    echo dictionary_examples(key, [(text: "fly", translation: "volar")], `from`="en", to="es")
