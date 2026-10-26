package reader

import "testing"

func TestCleanTextDecodesNestedEntities(t *testing.T) {
	for in, want := range map[string]string{
		"<p>Tom &amp;amp; Jerry</p>":   "Tom & Jerry",
		"it&amp;#39;s":                 "it's",
		"&lt;b&gt;bold&lt;/b&gt;":      "<b>bold</b>",
		"a&nbsp;\n  b":                 "a b",
		"&amp;amp;amp;amp;amp;":        "&amp;amp;",
	} {
		if got := cleanText(in); got != want {
			t.Errorf("cleanText(%q) = %q, want %q", in, got, want)
		}
	}
}
