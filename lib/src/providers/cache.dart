import 'package:diarme/src/models/note.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

final String tableNotesCache = 'note_cache';

class LocalCacheProvider {
  late Database db;

  Future open() async {
    final path = join(await getDatabasesPath(), 'online.diarme.db');
    db = await openDatabase(
      path,
      version: 4,
      onOpen: (db) => {
        db.execute('''
                create table if not exists $tableNotesCache (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                note_id text,
                title text,
                body text,
                created_at datetime default current_timestamp,
                is_starred tinyint,
                requires_sync tinyint default 0
              )
              ''')
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < newV) {
          try {
            await db.execute(
                "alter table $tableNotesCache add column requires_sync tinyint default 0;");
          } catch (ex) {
            debugPrint("Column is there");
          }
          try {
            await db.execute(
                "alter table $tableNotesCache add column created_at datetime default current_timestamp;");
          } catch (ex) {
            debugPrint("Column is there");
          }
        }
      },
    );
  }

  Future close() async => await db.close();
  // CACHE functions

  // update cache
  Future writeNotesToCatch(List<Note> notes) async {
    List<Map<String, dynamic>> notesRecords = notes
        .map((note) => {
              "note_id": note.id,
              "title": note.title,
              "body": note.body,
              "created_at": note.date,
              "is_starred": note.isStarred ? 1 : 0, // no boolean only tiny int
            })
        .toList();

    Batch batch = db.batch();
    notesRecords.forEach((record) {
      batch.insert(tableNotesCache, record);
    });
    await batch.commit(noResult: true);
  }

  Future flushCache() async {
    await db.delete(tableNotesCache, where: ' 1 = 1');
  }

  Future<int> getCachedNotesCount() async {
    int? count = Sqflite.firstIntValue(
        await db.rawQuery('select count(*) from $tableNotesCache'));
    return count ?? 0;
  }

  Future<List<Note>> getCachedNotes() async {
    try {
      List<Map> notes = await db.query(tableNotesCache);

      return notes.map((note) {
        bool isStarred = note['is_starred'] == 0 ? false : true;
        final DateFormat formatter = DateFormat.yMMMEd();
        var parsedDate;
        try {
          parsedDate = formatter.format(DateTime.parse(note['created_at']));
        } catch (ex) {
          parsedDate = note['created_at'];
        }
        var n = Note(
            id: note['note_id'],
            title: note['title'],
            body: note['body'],
            date: parsedDate,
            isStarred: isStarred);
        return n;
      }).toList();
    } catch (ex) {
      return [];
    }
  }

  Future<Note?> getCachedNote(String noteID) async {
    List<Map> notes = await db
        .query(tableNotesCache, where: 'note_id = ?', whereArgs: [noteID]);
    if (notes.isEmpty) {
      return null;
    }

    Map note = notes.first;
    bool isStarred = note['is_starred'] == 0 ? false : true;
    return Note(
        id: note['note_id'],
        title: note['title'],
        body: note['body'],
        date: note['created_at'],
        isStarred: isStarred);
  }

  Future updateCachedNote(Map<String, dynamic> note) async {
    note["requires_sync"] = 1;
    note["note_id"] = note["id"];
    note["is_starred"] = note['isStarred'] ? 1 : 0;
    note.remove('id');
    note.remove('isStarred');
    await db.update(tableNotesCache, note,
        where: 'note_id = ?', whereArgs: [note['note_id']]);
  }

  Future addNoteToCache(Map<String, dynamic> note) async {
    var now = new DateTime.now();
    note["requires_sync"] = 1;
    note["note_id"] = note["id"];
    note["is_starred"] = note['isStarred'] ? 1 : 0;
    note["created_at"] = now.toIso8601String();
    note.remove('isStarred');
    note.remove('id');
    await db.insert(tableNotesCache, note);
  }

  Future<List<Map<String, dynamic>>> getUnSyncedNotes() async {
    List<Map> records = await db
        .query(tableNotesCache, where: 'requires_sync = ?', whereArgs: [1]);

    List<Map<String, dynamic>> notes = records
        .map((record) => {
              "id": record['note_id'],
              "title": record['title'],
              "body": record['body'],
              "date": record['created_at'],
              "isStarred": record['is_starred'] == 0 ? false : true,
            })
        .toList();

    return notes;
  }
}
