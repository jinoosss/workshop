package memeland

import (
	"sort"
	"std"
	"strconv"
	"strings"
	"time"

	"gno.land/p/demo/avl"
	"gno.land/p/demo/seqid"
)

type Post struct {
	ID            string
	Data          string
	Author        std.Address
	Timestamp     time.Time
	UpvoteTracker *avl.Tree // address > struct{}{}
}

type Memeland struct {
	Posts       []*Post
	MemeCounter seqid.ID
}

// NewMemeland returns a pointer to a new Memeland object
// Initializes all the subfields
func NewMemeland() *Memeland {
	return &Memeland{
		Posts:       []*Post{},
		MemeCounter: 0,
	}
}

// PostMeme - Adds a new post at timestamp, with data
// Panics in case data is empty or timestamp is invalid
// Returns the ID of the created Post
func (m *Memeland) PostMeme(data string, timestamp int64) string {
	if data == "" || timestamp <= 0 {
		panic("timestamp or data cannot be empty")
	}

	id := m.MemeCounter.Next().String()

	newPost := &Post{
		ID:            id,
		Data:          data,
		Author:        std.PrevRealm().Addr(),
		Timestamp:     time.Unix(timestamp, 0),
		UpvoteTracker: avl.NewTree(),
	}

	m.Posts = append(m.Posts, newPost)
	return id
}

// Upvote increases the upvote count of a specific Post
// Panics if specified ID doesn't exist, or the user has already upvoted
func (m *Memeland) Upvote(id string) string {
	post := m.getPost(id)
	if post == nil {
		panic("post with specified ID does not exist")
	}

	caller := std.PrevRealm().Addr().String()

	if _, exists := post.UpvoteTracker.Get(caller); exists {
		panic("user has already upvoted this post")
	}

	post.UpvoteTracker.Set(caller, struct{}{})
	return "upvote successful"
}

// GetPostsInRange returns a JSON object containing marshalled Posts in a specific timestamp range
// Timestamps are given as Unix seconds
// Supports pagination
// sortBy can be "UPVOTES" (most upvotes-first), or "DATE_CREATED" (newest-first)
// Panics if page < 1, pageSize < 1, or pageSize > 10
// Returns empty JSON object if there are no posts in the specified range.
func (m *Memeland) GetPostsInRange(startTimestamp, endTimestamp int64, page, pageSize int, sortBy string) string {
	if len(m.Posts) == 0 {
		return "[]"
	}

	if page < 1 {
		panic("page count cannot be less than 1")
	}

	// No empty pages
	if pageSize < 1 {
		panic("page size cannot be less than 1")
	}

	// No pages larger than 10
	if pageSize > 10 {
		panic("page size cannot be larger than 10")
	}

	var filteredPosts []*Post

	start := time.Unix(startTimestamp, 0)
	end := time.Unix(endTimestamp, 0)

	// Filtering posts
	for _, p := range m.Posts {
		if !p.Timestamp.Before(start) && !p.Timestamp.After(end) {
			filteredPosts = append(filteredPosts, p)
		}
	}

	switch sortBy {
	// Sort by upvote descending
	case "UPVOTES":
		dateSorter := PostSorter{
			Posts: filteredPosts,
			LessF: func(i, j int) bool {
				return filteredPosts[i].UpvoteTracker.Size() > filteredPosts[j].UpvoteTracker.Size()
			},
		}
		sort.Sort(dateSorter)
	default:
		// Sort by timestamp, beginning with newest
		dateSorter := PostSorter{
			Posts: filteredPosts,
			LessF: func(i, j int) bool {
				return filteredPosts[i].Timestamp.After(filteredPosts[j].Timestamp)
			},
		}
		sort.Sort(dateSorter)
	}

	// Pagination
	startIndex := (page - 1) * pageSize
	endIndex := startIndex + pageSize

	// If page does not contain any posts
	if startIndex >= len(filteredPosts) {
		return "[]"
	}

	// If page contains fewer posts than the page size
	if endIndex > len(filteredPosts) {
		endIndex = len(filteredPosts)
	}

	// Return JSON representation of paginated and sorted posts
	return PostsToJSONString(filteredPosts[startIndex:endIndex])
}

// getPost gets a post by ID
func (m *Memeland) getPost(id string) *Post {
	for _, post := range m.Posts {
		if post.ID == id {
			return post
		}
	}

	return nil
}

// PostSorter is a flexible sorter for the *Post slice
type PostSorter struct {
	Posts []*Post
	LessF func(i, j int) bool
}

func (p PostSorter) Len() int {
	return len(p.Posts)
}

func (p PostSorter) Swap(i, j int) {
	p.Posts[i], p.Posts[j] = p.Posts[j], p.Posts[i]
}

func (p PostSorter) Less(i, j int) bool {
	return p.LessF(i, j)
}

// PostsToJSONString converts a slice of Post structs into a JSON string
func PostsToJSONString(posts []*Post) string {
	var sb strings.Builder
	sb.WriteString("[")

	for i, post := range posts {
		if i > 0 {
			sb.WriteString(",")
		}

		sb.WriteString(PostToJSONString(post))
	}
	sb.WriteString("]")

	return sb.String()
}

// PostToJSONString returns a Post formatted as a JSON string
func PostToJSONString(post *Post) string {
	var sb strings.Builder

	sb.WriteString("{")
	sb.WriteString(`"id":"` + post.ID + `",`)
	sb.WriteString(`"data":"` + escapeString(post.Data) + `",`)
	sb.WriteString(`"author":"` + escapeString(post.Author.String()) + `",`)
	sb.WriteString(`"timestamp":"` + strconv.Itoa(int(post.Timestamp.Unix())) + `",`)
	sb.WriteString(`"upvotes":` + strconv.Itoa(post.UpvoteTracker.Size()))
	sb.WriteString("}")

	return sb.String()
}

// escapeString escapes quotes in a string for JSON compatibility.
func escapeString(s string) string {
	return strings.ReplaceAll(s, `"`, `\"`)
}
