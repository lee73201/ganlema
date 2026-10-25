import Testing
import FocusDockCore

@Test func emptyFinalSpeechResultDoesNotEraseRecognizedWords() {
    var buffer = SpeechTranscriptBuffer()
    let accepted = buffer.accept("明天下午三点交报告")
    #expect(accepted)
    let emptyAccepted = buffer.accept("")
    #expect(!emptyAccepted)
    #expect(buffer.text == "明天下午三点交报告")
    #expect(buffer.ending(isFinal: true, hasError: false) == .complete)
    let nilAccepted = buffer.accept(nil)
    #expect(!nilAccepted)
    let whitespaceAccepted = buffer.accept(" \n\t ")
    #expect(!whitespaceAccepted)
    #expect(buffer.text == "明天下午三点交报告")
}

@Test func correctedSpeechResultsReplacePartialWordsWithoutConcatenatingDuplicates() {
    var buffer = SpeechTranscriptBuffer()
    buffer.accept("明天下午")
    buffer.accept("明天下午三点交抱告")
    buffer.accept("  明天下午三点交报告  ")
    #expect(buffer.text == "明天下午三点交报告")
    buffer.accept("明天下午三点交报告，后天上午十点开会")
    #expect(buffer.text == "明天下午三点交报告，后天上午十点开会")
}

@Test func speechFailureAndTimeoutKeepUsablePartialText() {
    var buffer = SpeechTranscriptBuffer()
    buffer.accept("后天上午十点开会")
    #expect(buffer.ending(isFinal: false, hasError: false) == .partial)
    #expect(buffer.ending(isFinal: true, hasError: true) == .partial)
    #expect(buffer.text == "后天上午十点开会")
}

@Test func noSpeechIsNeverReportedAsSuccessfulCapture() {
    var buffer = SpeechTranscriptBuffer()
    buffer.accept(" ")
    #expect(buffer.ending(isFinal: true, hasError: false) == .empty)
    #expect(buffer.ending(isFinal: false, hasError: true) == .empty)
    #expect(buffer.ending(isFinal: false, hasError: false) == .empty)
    buffer.accept("新录音")
    buffer = SpeechTranscriptBuffer()
    #expect(buffer.text.isEmpty)
}

@Test func unpunctuatedSpeechCanStillProduceTwoDatedTasks() {
    let cards = LocalTaskParser().parse("明天下午3:00交报告后天上午10:00开会")
    #expect(cards.count == 2)
    #expect(cards[0].draft.title == "交报告")
    #expect(cards[1].draft.title == "开会")
    #expect(cards[0].draft.dueDate != nil && cards[1].draft.dueDate != nil)
}
