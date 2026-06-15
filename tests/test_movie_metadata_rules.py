import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EDITOR = ROOT / "TicketWalletApp" / "Views" / "TicketRecordEditorView.swift"
SEARCH = ROOT / "TicketWalletApp" / "Views" / "TicketSearchView.swift"
MOVIE_SEARCH = ROOT / "TicketWalletApp" / "Views" / "MovieSearchView.swift"
SERVICE = ROOT / "TicketWalletApp" / "Services" / "MovieMetadataService.swift"


class MovieMetadataRulesTests(unittest.TestCase):
    def test_editor_blocks_save_until_required_movie_metadata_is_complete(self):
        content = EDITOR.read_text()
        self.assertIn("await ensureRequiredMovieMetadata()", content)
        self.assertIn("guard hasRequiredMovieMetadata else", content)
        self.assertIn("runtime != nil", content)
        self.assertIn("!doubanRating.trimmingCharacters", content)
        self.assertIn("豆瓣评分需要配置豆瓣资料代理后自动获取", content)

    def test_required_metadata_model_requires_douban_rating(self):
        content = SERVICE.read_text()
        required_block = content[content.index("var hasRequiredMovieInfo"):content.index("struct MovieMetadataService")]
        self.assertIn("!releaseDate.trimmingCharacters", required_block)
        self.assertIn("!director.trimmingCharacters", required_block)
        self.assertIn("runtimeMinutes != nil", required_block)
        self.assertIn("!doubanRating.trimmingCharacters", required_block)

    def test_movie_selection_entries_use_unified_metadata_service(self):
        search_content = SEARCH.read_text()
        movie_search_content = MOVIE_SEARCH.read_text()
        self.assertIn("private let metadataService = MovieMetadataService()", search_content)
        self.assertIn("private let metadataService = MovieMetadataService()", movie_search_content)
        self.assertIn("TicketRecordEditorView(initialMovieMetadata: metadata)", search_content)
        self.assertIn("let onSelect: (MovieMetadata) -> Void", movie_search_content)
        self.assertNotIn("let onSelect: (TMDBMovieSearchResult, TMDBMovieMetadata) -> Void", movie_search_content)
        self.assertNotIn("initialMetadata: TMDBMovieMetadata", EDITOR.read_text())


if __name__ == "__main__":
    unittest.main()
