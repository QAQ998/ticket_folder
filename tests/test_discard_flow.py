import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HOME = ROOT / "TicketWalletApp" / "Views" / "TicketWalletHomeView.swift"
EDITOR = ROOT / "TicketWalletApp" / "Views" / "TicketRecordEditorView.swift"
DETAIL = ROOT / "TicketWalletApp" / "Views" / "TicketRecordDetailView.swift"


class DiscardFlowTests(unittest.TestCase):
    def test_draft_entry_and_copy_are_removed(self):
        combined = "\n".join(path.read_text() for path in [HOME, EDITOR, DETAIL])
        forbidden = [
            "草稿箱",
            "是否保留当前内容",
            "保留后",
            "未完成草稿",
            "草稿详情",
            "saveDraftAndDismiss",
            "keepOnlyDraft",
            "draftForEditing",
        ]
        for text in forbidden:
            self.assertNotIn(text, combined)

    def test_editor_uses_delete_confirmation_for_unsaved_content(self):
        content = EDITOR.read_text()
        self.assertIn('"确认删除当前内容"', content)
        self.assertIn('Button("是", role: .destructive)', content)
        self.assertIn('Button("否", role: .cancel)', content)
        self.assertIn("interactiveDismissDisabled(shouldPromptForDiscard)", content)
        self.assertIn("DismissAttemptHandler(isDisabled: shouldPromptForDiscard)", content)
        self.assertIn("presentationControllerDidAttemptToDismiss", content)

    def test_home_does_not_resume_drafts(self):
        content = HOME.read_text()
        self.assertIn("TicketRecordEditorView()", content)
        self.assertIn("deleteExistingDrafts()", content)
        self.assertNotIn("TicketRecordEditorView(record:", content)


if __name__ == "__main__":
    unittest.main()
