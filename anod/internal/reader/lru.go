package reader

import (
	"container/list"
	"sync"
	"time"
)

// lru is a bounded cache: entries cost what the caller says (bytes for images,
// 1 for metadata) and the least recently used go once the total passes max.
// An entry may also expire (ttl > 0).
type lru struct {
	mu    sync.Mutex
	max   int64
	used  int64
	order *list.List // front = most recent
	items map[string]*list.Element
}

type lruEntry struct {
	key     string
	val     any
	cost    int64
	expires time.Time
}

func newLRU(max int64) *lru {
	return &lru{max: max, order: list.New(), items: map[string]*list.Element{}}
}

func (c *lru) get(key string) (any, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	el, ok := c.items[key]
	if !ok {
		return nil, false
	}
	e := el.Value.(*lruEntry)
	if !e.expires.IsZero() && time.Now().After(e.expires) {
		c.remove(el)
		return nil, false
	}
	c.order.MoveToFront(el)
	return e.val, true
}

func (c *lru) put(key string, val any, cost int64, ttl time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if cost > c.max { // never worth evicting everything for one entry
		return
	}
	if el, ok := c.items[key]; ok {
		c.remove(el)
	}
	e := &lruEntry{key: key, val: val, cost: cost}
	if ttl > 0 {
		e.expires = time.Now().Add(ttl)
	}
	c.items[key] = c.order.PushFront(e)
	c.used += cost
	for c.used > c.max {
		c.remove(c.order.Back())
	}
}

func (c *lru) setMax(max int64) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.max = max
	for c.used > c.max && c.order.Len() > 0 {
		c.remove(c.order.Back())
	}
}

func (c *lru) size() (n int, used int64) {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.order.Len(), c.used
}

func (c *lru) remove(el *list.Element) {
	e := el.Value.(*lruEntry)
	c.order.Remove(el)
	delete(c.items, e.key)
	c.used -= e.cost
}

// cached returns key's value or computes, stores and returns it. Errors are not cached.
func cached[T any](c *lru, key string, ttl time.Duration, fn func() (T, error)) (T, error) {
	if v, ok := c.get(key); ok {
		return v.(T), nil
	}
	v, err := fn()
	if err == nil {
		c.put(key, v, 1, ttl)
	}
	return v, err
}
