[
  # Custom keybindings
  {
    key = "ctrl+shift+p";
    command = "workbench.action.showCommands";
  }
  {
    key = "cmd+shift+p";
    command = "workbench.action.showCommands";
    when = "isMac";
  }
  {
    key = "ctrl+`";
    command = "workbench.action.terminal.toggleTerminal";
  }
  {
    key = "cmd+`";
    command = "workbench.action.terminal.toggleTerminal";
    when = "isMac";
  }

  # Disable all conflicting keybindings to avoid conflicts with Vim mode
  # This extensive list ensures Vim mode works properly without interference
  { key = "f12"; command = "-goToNextReference"; }
  { key = "f4"; command = "-goToNextReference"; }
  { key = "shift+f12"; command = "-goToPreviousReference"; }
  { key = "shift+f4"; command = "-goToPreviousReference"; }
  { key = "escape"; command = "-inlineChat.hideHint"; }
  { key = "alt+enter"; command = "-testing.editFocusedTest"; }
  { key = "escape"; command = "-notebook.cell.quitEdit"; }
  { key = "ctrl+enter"; command = "-notebook.cell.quitEdit"; }
  { key = "cmd+up"; command = "-chat.action.focus"; }
  { key = "shift+escape"; command = "-closeBreakpointWidget"; }
  { key = "f7"; command = "-editor.action.accessibleDiffViewer.next"; }
  { key = "shift+f7"; command = "-editor.action.accessibleDiffViewer.prev"; }
  { key = "alt+cmd+."; command = "-editor.action.autoFix"; }
  { key = "shift+alt+a"; command = "-editor.action.blockComment"; }
  { key = "cmd+f2"; command = "-editor.action.changeAll"; }
  { key = "shift+cmd+k"; command = "-editor.action.deleteLines"; }
  { key = "alt+f3"; command = "-editor.action.dirtydiff.next"; }
  { key = "shift+alt+f3"; command = "-editor.action.dirtydiff.previous"; }
  { key = "shift+enter"; command = "-editor.action.extensioneditor.findPrevious"; }
  { key = "shift+alt+f"; command = "-editor.action.formatDocument.none"; }
  { key = "cmd+f"; command = "-editor.action.formatSelection"; }
  { key = "cmd+down"; command = "-editor.action.goToBottomHover"; }
  { key = "cmd+f12"; command = "-editor.action.goToImplementation"; }
  { key = "shift+f12"; command = "-editor.action.goToReferences"; }
  { key = "cmd+up"; command = "-editor.action.goToTopHover"; }
  { key = "shift+cmd+."; command = "-editor.action.inPlaceReplace.down"; }
  { key = "shift+cmd+,"; command = "-editor.action.inPlaceReplace.up"; }
  { key = "cmd+]"; command = "-editor.action.indentLines"; }
  { key = "alt+]"; command = "-editor.action.inlineSuggest.showNext"; }
  { key = "alt+["; command = "-editor.action.inlineSuggest.showPrevious"; }
  { key = "alt+cmd+up"; command = "-editor.action.insertCursorAbove"; }
  { key = "shift+alt+i"; command = "-editor.action.insertCursorAtEndOfEachLineSelected"; }
  { key = "alt+cmd+down"; command = "-editor.action.insertCursorBelow"; }
  { key = "shift+cmd+enter"; command = "-editor.action.insertLineBefore"; }
  { key = "ctrl+j"; command = "-editor.action.joinLines"; }
  { key = "shift+cmd+\\"; command = "-editor.action.jumpToBracket"; }
  { key = "shift+cmd+f2"; command = "-editor.action.linkedEditing"; }
  { key = "alt+f8"; command = "-editor.action.marker.next"; }
  { key = "f8"; command = "-editor.action.marker.nextInFiles"; }
  { key = "shift+alt+f8"; command = "-editor.action.marker.prev"; }
  { key = "shift+f8"; command = "-editor.action.marker.prevInFiles"; }
  { key = "alt+f9"; command = "-editor.action.nextCommentThreadAction"; }
  { key = "f3"; command = "-editor.action.nextMatchFindAction"; }
  { key = "cmd+g"; command = "-editor.action.nextMatchFindAction"; }
  { key = "enter"; command = "-editor.action.nextMatchFindAction"; }
  { key = "cmd+f3"; command = "-editor.action.nextSelectionMatchFindAction"; }
  { key = "shift+alt+o"; command = "-editor.action.organizeImports"; }
  { key = "cmd+["; command = "-editor.action.outdentLines"; }
  { key = "shift+cmd+f12"; command = "-editor.action.peekImplementation"; }
  { key = "shift+alt+f9"; command = "-editor.action.previousCommentThreadAction"; }
  { key = "cmd+k alt+cmd+up"; command = "-editor.action.previousCommentingRange"; }
  { key = "shift+f3"; command = "-editor.action.previousMatchFindAction"; }
  { key = "shift+cmd+g"; command = "-editor.action.previousMatchFindAction"; }
  { key = "shift+enter"; command = "-editor.action.previousMatchFindAction"; }
  { key = "shift+cmd+f3"; command = "-editor.action.previousSelectionMatchFindAction"; }
  { key = "cmd+."; command = "-editor.action.quickFix"; }
  { key = "ctrl+shift+r"; command = "-editor.action.refactor"; }
  { key = "f12"; command = "-editor.action.revealDefinition"; }
  { key = "cmd+f12"; command = "-editor.action.revealDefinition"; }
  { key = "cmd+k f12"; command = "-editor.action.revealDefinitionAside"; }
  { key = "cmd+k cmd+f12"; command = "-editor.action.revealDefinitionAside"; }
  { key = "escape"; command = "-editor.action.selectEditor"; }
  { key = "cmd+k cmd+k"; command = "-editor.action.selectFromAnchorToCursor"; }
  { key = "shift+cmd+l"; command = "-editor.action.selectHighlights"; }
  { key = "shift+f10"; command = "-editor.action.showContextMenu"; }
  { key = "cmd+k cmd+i"; command = "-editor.action.showHover"; }
  { key = "ctrl+shift+right"; command = "-editor.action.smartSelect.expand"; }
  { key = "ctrl+shift+cmd+right"; command = "-editor.action.smartSelect.expand"; }
  { key = "ctrl+shift+left"; command = "-editor.action.smartSelect.shrink"; }
  { key = "ctrl+shift+cmd+left"; command = "-editor.action.smartSelect.shrink"; }
  { key = "alt+cmd+f"; command = "-editor.action.startFindReplaceAction"; }
  { key = "ctrl+shift+m"; command = "-editor.action.toggleTabFocusMode"; }
  { key = "shift+cmd+space"; command = "-editor.action.triggerParameterHints"; }
  { key = "cmd+i"; command = "-editor.action.triggerSuggest"; }
  { key = "alt+escape"; command = "-editor.action.triggerSuggest"; }
  { key = "ctrl+space"; command = "-editor.action.triggerSuggest"; }
  { key = "enter"; command = "-editor.action.webvieweditor.findNext"; }
  { key = "shift+enter"; command = "-editor.action.webvieweditor.findPrevious"; }
  { key = "escape"; command = "-editor.action.webvieweditor.hideFind"; }
  { key = "cmd+f"; command = "-editor.action.webvieweditor.showFind"; }
  { key = "escape"; command = "-editor.cancelOperation"; }
  { key = "cmd+."; command = "-editor.changeDropType"; }
  { key = "cmd+."; command = "-editor.changePasteType"; }
  { key = "cmd+k cmd+,"; command = "-editor.createFoldingRangeFromSelection"; }
  { key = "escape"; command = "-editor.debug.action.closeExceptionWidget"; }
  { key = "cmd+k cmd+i"; command = "-editor.debug.action.showDebugHover"; }
  { key = "f9"; command = "-editor.debug.action.toggleBreakpoint"; }
  { key = "tab"; command = "-editor.emmet.action.expandAbbreviation"; }
  { key = "alt+cmd+["; command = "-editor.fold"; }
  { key = "cmd+k cmd+0"; command = "-editor.foldAll"; }
  { key = "cmd+k cmd+/"; command = "-editor.foldAllBlockComments"; }
  { key = "cmd+k cmd+-"; command = "-editor.foldAllExcept"; }
  { key = "cmd+k cmd+8"; command = "-editor.foldAllMarkerRegions"; }
  { key = "cmd+k cmd+1"; command = "-editor.foldLevel1"; }
  { key = "cmd+k cmd+2"; command = "-editor.foldLevel2"; }
  { key = "cmd+k cmd+3"; command = "-editor.foldLevel3"; }
  { key = "cmd+k cmd+4"; command = "-editor.foldLevel4"; }
  { key = "cmd+k cmd+5"; command = "-editor.foldLevel5"; }
  { key = "cmd+k cmd+6"; command = "-editor.foldLevel6"; }
  { key = "cmd+k cmd+7"; command = "-editor.foldLevel7"; }
  { key = "cmd+k cmd+["; command = "-editor.foldRecursively"; }
  { key = "f12"; command = "-editor.gotoNextSymbolFromResult"; }
  { key = "escape"; command = "-editor.gotoNextSymbolFromResult.cancel"; }
  { key = "escape"; command = "-editor.hideDropWidget"; }
  { key = "escape"; command = "-editor.hidePasteWidget"; }
  { key = "cmd+k cmd+."; command = "-editor.removeManualFoldingRanges"; }
  { key = "cmd+k cmd+l"; command = "-editor.toggleFold"; }
  { key = "cmd+k shift+cmd+l"; command = "-editor.toggleFoldRecursively"; }
  { key = "alt+cmd+]"; command = "-editor.unfold"; }
  { key = "cmd+k cmd+j"; command = "-editor.unfoldAll"; }
  { key = "cmd+k cmd+="; command = "-editor.unfoldAllExcept"; }
  { key = "cmd+k cmd+9"; command = "-editor.unfoldAllMarkerRegions"; }
  { key = "cmd+k cmd+]"; command = "-editor.unfoldRecursively"; }
  { key = "escape"; command = "-inlayHints.stopReadingLineWithHint"; }
  { key = "escape"; command = "-inlineChat.discardHunkChange"; }
  { key = "tab"; command = "-insertSnippet"; }
  { key = "shift+enter"; command = "-interactive.execute"; }
  { key = "enter"; command = "-interactive.execute"; }
  { key = "escape"; command = "-notebook.cell.chat.discard"; }
  { key = "pagedown"; command = "-notebook.cell.cursorPageDown"; }
  { key = "shift+pagedown"; command = "-notebook.cell.cursorPageDownSelect"; }
  { key = "pageup"; command = "-notebook.cell.cursorPageUp"; }
  { key = "shift+pageup"; command = "-notebook.cell.cursorPageUpSelect"; }
  { key = "ctrl+enter"; command = "-notebook.cell.execute"; }
  { key = "alt+enter"; command = "-notebook.cell.executeAndInsertBelow"; }
  { key = "shift+enter"; command = "-notebook.cell.executeAndSelectBelow"; }
  { key = "shift+alt+f"; command = "-notebook.formatCell"; }
  { key = "ctrl+enter"; command = "-openReferenceToSide"; }
  { key = "enter"; command = "-repl.action.acceptInput"; }
  { key = "cmd+f"; command = "-repl.action.filter"; }
  { key = "alt+cmd+f"; command = "-repl.action.find"; }
  { key = "shift+enter"; command = "-repl.execute"; }
  { key = "enter"; command = "-repl.execute"; }
  { key = "alt+end alt+end"; command = "-repl.focusLastItemExecuted"; }
  { key = "shift+cmd+r"; command = "-rerunSearchEditorSearch"; }
  { key = "escape"; command = "-search.action.focusQueryEditorWidget"; }
  { key = "shift+cmd+backspace"; command = "-search.searchEditor.action.deleteFileResults"; }
  { key = "escape"; command = "-settings.action.clearSearchResults"; }
  { key = "cmd+f"; command = "-settings.action.search"; }
  { key = "cmd+i"; command = "-settings.action.toggleAiSearch"; }
  { key = "cmd+/"; command = "-toggleExplainMode"; }
  { key = "cmd+k f2"; command = "-togglePeekWidgetFocus"; }
  { key = "escape"; command = "-welcome.goBack"; }
  { key = "cmd+/"; command = "-workbench.action.chat.attachContext"; }
  { key = "ctrl+alt+enter"; command = "-workbench.action.chat.runInTerminal"; }
  { key = "enter"; command = "-workbench.action.chat.submit"; }
  { key = "shift+alt+enter"; command = "-workbench.action.chat.submitWithoutDispatching"; }
  { key = "cmd+."; command = "-workbench.action.chat.toggleAgentMode"; }
  { key = "alt+f5"; command = "-workbench.action.editor.nextChange"; }
  { key = "shift+alt+f5"; command = "-workbench.action.editor.previousChange"; }
  { key = "enter"; command = "-workbench.action.edits.submit"; }
  { key = "shift+escape"; command = "-workbench.action.hideComment"; }
  { key = "escape"; command = "-workbench.action.hideComment"; }
  { key = "cmd+right"; command = "-editor.action.inlineSuggest.acceptNextWord"; }
  { key = "escape"; command = "-inlineChat.close"; }
  { key = "alt+f8"; command = "-testing.goToNextMessage"; }
  { key = "shift+alt+f8"; command = "-testing.goToPreviousMessage"; }
  { key = "shift+escape"; command = "-closeFindWidget"; }
  { key = "escape"; command = "-closeFindWidget"; }
  { key = "alt+cmd+enter"; command = "-editor.action.replaceAll"; }
  { key = "shift+cmd+1"; command = "-editor.action.replaceOne"; }
  { key = "ctrl+n"; command = "-showNextParameterHint"; }
  { key = "alt+down"; command = "-showNextParameterHint"; }
  { key = "ctrl+p"; command = "-showPrevParameterHint"; }
  { key = "alt+up"; command = "-showPrevParameterHint"; }
  { key = "shift+tab"; command = "-acceptAlternativeSelectedSuggestion"; }
  { key = "shift+enter"; command = "-acceptAlternativeSelectedSuggestion"; }
  { key = "cmd+i"; command = "-focusSuggestion"; }
  { key = "ctrl+space"; command = "-focusSuggestion"; }
  { key = "shift+escape"; command = "-hideSuggestWidget"; }
  { key = "escape"; command = "-hideSuggestWidget"; }
  { key = "shift+tab"; command = "-insertPrevSuggestion"; }
  { key = "cmd+pagedown"; command = "-selectNextPageSuggestion"; }
  { key = "pagedown"; command = "-selectNextPageSuggestion"; }
  { key = "ctrl+n"; command = "-selectNextSuggestion"; }
  { key = "cmd+down"; command = "-selectNextSuggestion"; }
  { key = "cmd+pageup"; command = "-selectPrevPageSuggestion"; }
  { key = "ctrl+p"; command = "-selectPrevSuggestion"; }
  { key = "cmd+up"; command = "-selectPrevSuggestion"; }
  { key = "cmd+i"; command = "-toggleSuggestionDetails"; }
  { key = "ctrl+space"; command = "-toggleSuggestionDetails"; }
  { key = "ctrl+alt+space"; command = "-toggleSuggestionFocus"; }
  { key = "shift+escape"; command = "-cancelLinkedEditingInput"; }
  { key = "shift+escape"; command = "-cancelRenameInput"; }
  { key = "cmd+k cmd+i"; command = "-workbench.action.showHover"; }
  { key = "shift+cmd+l"; command = "-addCursorsAtSearchResults"; }
  { key = "shift+cmd+;"; command = "-breadcrumbs.focus"; }
  { key = "shift+cmd+."; command = "-breadcrumbs.focusAndSelect"; }
  { key = "shift+cmd+."; command = "-breadcrumbs.toggleToOn"; }
  { key = "cmd+down"; command = "-chat.action.focus"; }
  { key = "cmd+backspace"; command = "-chatEditing.discardAllFiles"; }
  { key = "alt+f5"; command = "-chatEditor.action.navigateNext"; }
  { key = "shift+alt+f5"; command = "-chatEditor.action.navigatePrevious"; }
  { key = "f7"; command = "-chatEditor.action.showAccessibleDiffView"; }
  { key = "shift+alt+f7"; command = "-chatEditor.action.toggleDiff"; }
  { key = "cmd+f"; command = "-commentsFocusFilter"; }
  { key = "cmd+down"; command = "-commentsFocusViewFromFilter"; }
  { key = "cmd+left"; command = "-cursorWordAccessibilityLeft"; }
  { key = "shift+cmd+left"; command = "-cursorWordAccessibilityLeftSelect"; }
  { key = "cmd+right"; command = "-cursorWordAccessibilityRight"; }
  { key = "shift+cmd+right"; command = "-cursorWordAccessibilityRightSelect"; }
  { key = "alt+-"; command = "-decreaseSearchEditorContextLines"; }
  { key = "alt+f1"; command = "-editor.action.accessibilityHelp"; }
  { key = "alt+a"; command = "-editor.action.accessibilityHelpConfigureAssignedKeybindings"; }
  { key = "alt+k"; command = "-editor.action.accessibilityHelpConfigureKeybindings"; }
  { key = "alt+h"; command = "-editor.action.accessibilityHelpOpenHelpLink"; }
  { key = "alt+f2"; command = "-editor.action.accessibleView"; }
  { key = "alt+f6"; command = "-editor.action.accessibleViewDisableHint"; }
  { key = "alt+]"; command = "-editor.action.accessibleViewNext"; }
  { key = "alt+cmd+pagedown"; command = "-editor.action.accessibleViewNextCodeBlock"; }
  { key = "alt+["; command = "-editor.action.accessibleViewPrevious"; }
  { key = "alt+cmd+pageup"; command = "-editor.action.accessibleViewPreviousCodeBlock"; }
  { key = "cmd+k"; command = "-editor.action.defineKeybinding"; }
  { key = "alt+cmd+o"; command = "-editor.action.toggleOvertypeInsertMode"; }
  { key = "shift+alt+d"; command = "-editor.detectLanguage"; }
  { key = "shift+enter"; command = "-editor.refocusCallHierarchy"; }
  { key = "shift+enter"; command = "-editor.refocusTypeHierarchy"; }
  { key = "shift+alt+h"; command = "-editor.showCallHierarchy"; }
  { key = "shift+alt+h"; command = "-editor.showIncomingCalls"; }
  { key = "shift+alt+h"; command = "-editor.showOutgoingCalls"; }
  { key = "shift+alt+h"; command = "-editor.showSubtypes"; }
  { key = "shift+alt+h"; command = "-editor.showSupertypes"; }
  { key = "shift+alt+f"; command = "-filesExplorer.findInFolder"; }
  { key = "alt+down"; command = "-history.showNext"; }
  { key = "alt+up"; command = "-history.showPrevious"; }
  { key = "enter"; command = "-iconSelectBox.selectFocused"; }
  { key = "alt+="; command = "-increaseSearchEditorContextLines"; }
  { key = "cmd+i"; command = "-inlineChat.holdForSpeech"; }
  { key = "f7"; command = "-inlineChat.moveToNextHunk"; }
  { key = "shift+f7"; command = "-inlineChat.moveToPreviousHunk"; }
  { key = "cmd+r"; command = "-inlineChat.regenerate"; }
  { key = "cmd+i"; command = "-inlineChat.start"; }
  { key = "cmd+k i"; command = "-inlineChat.startWithCurrentLine"; }
  { key = "cmd+z"; command = "-inlineChat.unstash"; }
  { key = "cmd+down"; command = "-inlineChat.viewInChat"; }
  { key = "cmd+i"; command = "-inlineChat2.close"; }
  { key = "escape"; command = "-inlineChat2.close"; }
  { key = "cmd+i"; command = "-inlineChat2.reveal"; }
  { key = "cmd+up"; command = "-interactive.history.focus"; }
  { key = "cmd+down"; command = "-interactive.scrollToBottom"; }
  { key = "cmd+up"; command = "-interactive.scrollToTop"; }
  { key = "enter"; command = "-keybindings.editor.acceptWhenExpression"; }
  { key = "cmd+k cmd+a"; command = "-keybindings.editor.addKeybinding"; }
  { key = "escape"; command = "-keybindings.editor.clearSearchResults"; }
  { key = "enter"; command = "-keybindings.editor.defineKeybinding"; }
  { key = "cmd+k cmd+e"; command = "-keybindings.editor.defineWhenExpression"; }
  { key = "cmd+down"; command = "-keybindings.editor.focusKeybindings"; }
  { key = "alt+cmd+k"; command = "-keybindings.editor.recordSearchKeys"; }
  { key = "escape"; command = "-keybindings.editor.rejectWhenExpression"; }
  { key = "cmd+backspace"; command = "-keybindings.editor.removeKeybinding"; }
  { key = "cmd+f"; command = "-keybindings.editor.searchKeybindings"; }
  { key = "alt+cmd+p"; command = "-keybindings.editor.toggleSortByPrecedence"; }
  { key = "escape"; command = "-list.clear"; }
  { key = "escape"; command = "-list.closeFind"; }
  { key = "cmd+up"; command = "-list.collapse"; }
  { key = "shift+cmd+up"; command = "-list.collapseAll"; }
  { key = "cmd+left"; command = "-list.collapseAll"; }
  { key = "shift+down"; command = "-list.expandSelectionDown"; }
  { key = "shift+up"; command = "-list.expandSelectionUp"; }
  { key = "f3"; command = "-list.find"; }
  { key = "alt+cmd+f"; command = "-list.find"; }
  { key = "ctrl+alt+n"; command = "-list.focusAnyDown"; }
  { key = "alt+down"; command = "-list.focusAnyDown"; }
  { key = "alt+home"; command = "-list.focusAnyFirst"; }
  { key = "alt+end"; command = "-list.focusAnyLast"; }
  { key = "ctrl+alt+p"; command = "-list.focusAnyUp"; }
  { key = "alt+up"; command = "-list.focusAnyUp"; }
  { key = "ctrl+n"; command = "-list.focusDown"; }
  { key = "home"; command = "-list.focusFirst"; }
  { key = "end"; command = "-list.focusLast"; }
  { key = "pagedown"; command = "-list.focusPageDown"; }
  { key = "pageup"; command = "-list.focusPageUp"; }
  { key = "ctrl+p"; command = "-list.focusUp"; }
  { key = "cmd+down"; command = "-list.scrollDown"; }
  { key = "cmd+up"; command = "-list.scrollUp"; }
  { key = "cmd+down"; command = "-list.select"; }
  { key = "enter"; command = "-list.select"; }
  { key = "cmd+a"; command = "-list.selectAll"; }
  { key = "cmd+k cmd+i"; command = "-list.showHover"; }
  { key = "space"; command = "-list.toggleExpand"; }
  { key = "shift+cmd+enter"; command = "-list.toggleSelection"; }
]
