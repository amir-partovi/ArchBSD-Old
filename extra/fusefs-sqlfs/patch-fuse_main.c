--- fuse_main.c.orig	Wed Oct 25 19:28:26 2006
+++ fuse_main.c	Wed Feb  7 21:34:03 2007
@@ -17,12 +17,60 @@
 
 *****************************************************************************/
 
+#include <stdlib.h>
+#include <stdio.h>
+#include <sysexits.h>
 #include "sqlfs.h"
 
+void usage() __dead2;
+
+void usage()
+{
+	fprintf(stderr, "Usage: %s -o dbname [-h] dir\n", getprogname());
+
+	exit(EX_USAGE);
+}
 
 int main(int argc, char **argv)
 {
-    sqlfs_init("/tmp/fsdata");
+	char c;
+	int ret;
+	char *dbname = NULL;
+	char *args[2];
+	char *prog = argv[0];
+	
+	while ((c = getopt(argc, argv, "o:h")) != -1)
+		switch (c) {
+		case 'o':
+			dbname = strdup(optarg);
+			break;
+		case 'h':
+			/* FALLTHROUGH */
+		default:
+			usage();
+			/* NOTREACHED */
+		}
+		argc -= optind;
+		argv += optind;
+
+	if (dbname == NULL) {
+		dbname = getenv("SQLFS_DBNAME");
+	}
+
+	if (dbname == NULL || argc < 1)
+		usage();
+	/* NOTREACHED */
+
+	ret = sqlfs_init(dbname);
+	if (ret != 0)
+		return ret;
+
+	fprintf(stderr, "init\n");
+
+	args[0] = strdup(getprogname());
+	args[1] = strdup(argv[0]);
    
-    return sqlfs_fuse_main(argc, argv);
+	ret = sqlfs_fuse_main(2, args);
+	
+	return ret;
 }
