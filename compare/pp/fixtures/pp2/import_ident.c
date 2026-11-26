/* #import reads a file once, #ident and #sccs reach clang's output as #ident lines */
#import "imported.h"
#import "imported.h"
#include "imported.h"
#ident "import_ident 1"
#sccs "import_ident 2"
int after_import;
