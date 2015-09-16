CREATE TABLE "ctf" (
	"id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
	"name" TEXT NOT NULL
);
CREATE TABLE "challenge" (
	"id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
	"title" TEXT NOT NULL,
	"category" TEXT NOT NULL,
	"points" INTEGER NOT NULL,
	"done" INTEGER NOT NULL DEFAULT (0),
	"ctf" INTEGER NOT NULL
);
CREATE TABLE "assigned" (
	"user" TEXT NOT NULL,
	"challenge" INTEGER NOT NULL
);
CREATE TABLE user (
	"name" TEXT PRIMARY KEY NOT NULL,
	"pwhash" TEXT NOT NULL,
	"sessid" TEXT,
	"scope" INTEGER NOT NULL DEFAULT (0),
	"apikey" TEXT
);
CREATE TABLE file (
	"id" TEXT PRIMARY KEY NOT NULL,
	"name" TEXT NOT NULL,
	"user" INTEGER NOT NULL,
	"ctf" INTEGER,
	"challenge" INTEGER,
	"uploaded" INTEGER NOT NULL DEFAULT (0),
	"mimetype" TEXT DEFAULT ('application/octet-stream; charset=binary')
);
