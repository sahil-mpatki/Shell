/* Debian trixie's libelf.a/libdw.a (elfutils 0.192) reference these but
 * leave out eu-search.o, so static links fail. Same definitions as
 * elfutils' lib/eu-search.c built without thread safety (Debian's build):
 * the tree is { void *root; int lock; } and the lock is unused. */
#define _GNU_SOURCE
#include <search.h>

typedef struct { void *root; int lock; } search_tree;
typedef int (*cmp_fn)(const void *, const void *);

void *eu_tsearch(const void *key, search_tree *t, cmp_fn c) { return tsearch(key, &t->root, c); }
void *eu_tfind(const void *key, search_tree *t, cmp_fn c) { return tfind(key, &t->root, c); }
void *eu_tdelete(const void *key, search_tree *t, cmp_fn c) { return tdelete(key, &t->root, c); }
void eu_tdestroy(search_tree *t, void (*free_node)(void *)) { tdestroy(t->root, free_node); t->root = 0; }
void eu_search_tree_init(search_tree *t) { t->root = 0; t->lock = 0; }
void eu_search_tree_fini(search_tree *t, void (*free_node)(void *)) { eu_tdestroy(t, free_node); }
