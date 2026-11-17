// Structs, pointers and the heap: a linked list built, reversed and freed.
#include <stdio.h>
#include <stdlib.h>

struct node {
    int value;
    struct node *next;
};

static struct node *push(struct node *head, int value)
{
    struct node *n = malloc(sizeof *n);
    n->value = value;
    n->next = head;
    return n;
}

static struct node *reverse(struct node *head)
{
    struct node *prev = NULL;
    while (head) {
        struct node *next = head->next;
        head->next = prev;
        prev = head;
        head = next;
    }
    return prev;
}

int main(void)
{
    struct node *list = NULL;
    for (int i = 1; i <= 5; i++)
        list = push(list, i * i);
    list = reverse(list);
    for (struct node *p = list; p; p = p->next)
        printf("%d%s", p->value, p->next ? " -> " : "\n");
    while (list) {
        struct node *next = list->next;
        free(list);
        list = next;
    }
    return 0;
}
