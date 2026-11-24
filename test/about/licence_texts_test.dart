// M1.9a (AC1, AC7, review note R6): the SQLite3 Multiple Ciphers notice carries
// the licence text of every bundled part, word for word from the project at
// tag v2.7.1 (first checked at v2.5.0; M1.10b re-checked every quoted file at
// v2.7.1). A later edit of assets/licences/sqlite3mc.txt cannot drop a
// copyright holder or a licence text without one of these failing.
//
// The expected lines below were read from the files named in each group at
// https://github.com/utelle/SQLite3MultipleCiphers (tag v2.7.1). Spaces and
// line breaks do not count: both sides are compared with every run of white
// space turned into one space.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/about/licences.dart';

String squash(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

const _tag = 'v2.7.1';

/// The MIT permission text and warranty disclaimer, as in `LICENSE` and in
/// the header of `src/miniz.c`.
const _mit = [
  'Permission is hereby granted, free of charge, to any person obtaining a '
      'copy of this software and associated documentation files (the '
      '"Software"), to deal in the Software without restriction, including '
      'without limitation the rights to use, copy, modify, merge, publish, '
      'distribute, sublicense, and/or sell copies of the Software, and to '
      'permit persons to whom the Software is furnished to do so, subject to '
      'the following conditions:',
  'The above copyright notice and this permission notice shall be included in '
      'all copies or substantial portions of the Software.',
  'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR '
      'IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF '
      'MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. '
      'IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY '
      'CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, '
      'TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE '
      'SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.',
];

const _blessing = [
  'The author disclaims copyright to this source code. In place of a legal '
      'notice, here is a blessing:',
  'May you do good and not evil.',
  'May you find forgiveness for yourself and forgive others.',
  'May you share freely, never taking more than you give.',
];

/// One bundled part: the start of its block in the notice, the files whose
/// text it quotes, and lines that must be in its block.
class _Part {
  const _Part(this.heading, this.files, this.lines);
  final String heading;
  final List<String> files;
  final List<String> lines;
}

const _parts = <_Part>[
  _Part(
    '* SQLite3 Multiple Ciphers own code',
    ['LICENSE'],
    [
      'MIT License',
      'Copyright (c) 2019-2026 Ulrich Telle',
      ..._mit,
      // M1.10b: new own code in 2.7.x (header "License: MIT").
      'hwcheck.c',
    ],
  ),
  _Part(
    '* AEGIS (src/aegis)',
    ['src/aegis/include/aegis.h', 'src/aegis/common/common.c'],
    ['Copyright: (c) 2023-2024 Frank Denis', 'SPDX-License-Identifier: MIT'],
  ),
  _Part(
    '* Ascon (src/ascon)',
    ['src/ascon/aead.c', 'src/ascon/pbkdf2.c', 'src/ascon/api.h'],
    [
      'Based on: Public domain Ascon reference implementation',
      '(see https://github.com/ascon/ascon-c)',
      'Copyright: (c) 2023-2023 Ulrich Telle',
      'Copyright: (c) 2023-2026 Ulrich Telle',
      'License: MIT',
      'by Rhys Weatherley, Southern Storm Software, Pty Ltd.',
    ],
  ),
  _Part('* Ascon helper files', [], ['No licence text in the file']),
  _Part(
    '* aes_hardware.c',
    ['src/aes_hardware.c', 'src/memory_secure.c'],
    [
      'Copyright: (c) 2020 Ulrich Telle',
      'Copyright: (c) 2023 Ulrich Telle',
      'License: MIT',
    ],
  ),
  _Part('* argon2/libargon2.c', [], ['No licence text in the file']),
  _Part('* mystdint.h', [], ['No licence text in the file']),
  _Part(
    '* ChaCha20 and Poly1305 (chacha20poly1305.c)',
    ['src/chacha20poly1305.c', 'src/csprng_entropy.c'],
    [
      'The code was taken from the public domain implementation of the sqleet '
          'project (https://github.com/resilar/sqleet)',
      'The code was separated from the ChaCha20-Poly1305 implementation.',
    ],
  ),
  // M1.10b: new in 2.7.x, a copy of libsodium's ChaCha20 and Poly1305 code.
  _Part(
    '* ChaCha20 and Poly1305 from libsodium (src/chacha20)',
    ['src/chacha20/src/LICENSE', 'src/chacha20/src/ref/chacha20_ref.c'],
    [
      'ISC License',
      'Copyright (c) 2013-2026 Frank Denis <j at pureftpd dot org>',
      'Permission to use, copy, modify, and/or distribute this software for '
          'any purpose with or without fee is hereby granted, provided that '
          'the above copyright notice and this permission notice appear in '
          'all copies.',
      'THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL '
          'WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED '
          'WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE '
          'AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR '
          'CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS '
          'OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, '
          'NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN '
          'CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.',
      'chacha-merged.c version 20080118 D. J. Bernstein Public domain.',
      'libchacha20.c',
    ],
  ),
  _Part(
    '* AES / Rijndael',
    ['src/rijndael.c'],
    [
      'Copyright: (c) 2006-2020 Ulrich Telle',
      'License: MIT',
      'The original code is public domain',
      'Author : Szymon Stefanek (stefanek@tin.it)',
      'authors: v1.0: Antoon Bosselaers',
      'This code is placed in the public domain.',
    ],
  ),
  _Part(
    '* SHA-1 (sha1.c), MD5 (md5.c)',
    ['src/sha1.c', 'src/md5.c'],
    [
      'By Steve Reid <sreid@sea-to-sky.net> 100% Public Domain',
      'By Ulrich Telle <github@telle-online.de> Still 100% public domain',
      'Author: Alexander Peslyak, better known as Solar Designer',
      'No copyright is claimed, and the software is hereby placed in the '
          'public domain.',
      'Copyright (c) 2001 Alexander Peslyak',
    ],
  ),
  _Part(
    '* SHA-2 (sha2.c)',
    ['src/sha2.c'],
    [
      'Copyright (C) 2005, 2007 Olivier Gay <olivier.gay@a3.epfl.ch> '
          'All rights reserved.',
      'Redistribution and use in source and binary forms, with or without '
          'modification, are permitted provided that the following '
          'conditions are met:',
      '1. Redistributions of source code must retain the above copyright '
          'notice, this list of conditions and the following disclaimer.',
      '2. Redistributions in binary form must reproduce the above copyright '
          'notice, this list of conditions and the following disclaimer in '
          'the documentation and/or other materials provided with the '
          'distribution.',
      '3. Neither the name of the project nor the names of its contributors '
          'may be used to endorse or promote products derived from this '
          'software without specific prior written permission.',
      "THIS SOFTWARE IS PROVIDED BY THE PROJECT AND CONTRIBUTORS ``AS IS'' "
          'AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED '
          'TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A '
          'PARTICULAR PURPOSE ARE DISCLAIMED.',
      'OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF '
          'SUCH DAMAGE.',
    ],
  ),
  _Part(
    '* PBKDF2 (fastpbkdf2.c)',
    ['src/fastpbkdf2.c'],
    [
      'Written in 2015 by Joseph Birr-Pixton <jpixton@gmail.com>',
      'To the extent possible under law, the author(s) have dedicated all '
          'copyright and related and neighboring rights to this software to '
          'the public domain worldwide.',
      'You should have received a copy of the CC0 Public Domain Dedication '
          'along with this software.',
      '<http://creativecommons.org/publicdomain/zero/1.0/>',
    ],
  ),
  _Part(
    '* Argon2 (src/argon2',
    ['src/argon2/src/argon2.c'],
    [
      'Copyright 2015 Daniel Dinu, Dmitry Khovratovich, Jean-Philippe '
          'Aumasson, and Samuel Neves',
      'You may use this work under the terms of a Creative Commons CC0 1.0 '
          'License/Waiver or the Apache Public License 2.0, at your option.',
      '- CC0 1.0 Universal : https://creativecommons.org/publicdomain/zero/1.0',
      '- Apache 2.0 : https://www.apache.org/licenses/LICENSE-2.0',
    ],
  ),
  _Part(
    '* SQLite3 Multiple Ciphers RC4 cipher',
    ['src/cipher_sds_rc4.c', 'src/cipher_sqlcipher.c'],
    [
      'Copyright: (c) 2006-2024 Ulrich Telle',
      'Copyright: (c) 2006-2026 Ulrich Telle',
      'License: MIT',
    ],
  ),
  _Part(
    '* miniz (miniz.c',
    ['src/miniz.c'],
    [
      'Copyright 2013-2014 RAD Game Tools and Valve Software',
      'Copyright 2010-2014 Rich Geldreich and Tenacious Software LLC',
      'All Rights Reserved.',
      ..._mit,
    ],
  ),
  _Part(
    '* SQLite core and SQLite extensions',
    ['src/csv.c', 'src/rekeyvacuum.c', 'src/btreecopyfile.c'],
    [..._blessing, '2016-05-28', '2020-11-14', 'btreecopyfile.c'],
  ),
  _Part(
    '* vsv.c (extension)',
    ['src/vsv.c'],
    [
      '2020-02-08 modified by Keith Medcalf who also disclaims all copyright '
          'on the modifications and hereby places this code in the public '
          'domain',
    ],
  ),
  _Part('* extensionfunctions.c', [], ['No licence text.']),
];

void main() {
  late List<String> blocks;
  late String notice;
  setUpAll(() {
    notice = File(sqlite3mcNoticesAsset).readAsStringSync();
    blocks = [
      for (final b in notice.split(RegExp(r'\n(?=\* )')))
        if (b.startsWith('* ')) b.trim(),
    ];
  });

  test('one block per bundled part, in the order of docs/licences.md', () {
    expect(blocks, hasLength(_parts.length));
    for (var i = 0; i < _parts.length; i++) {
      expect(blocks[i], startsWith(_parts[i].heading), reason: 'block $i');
    }
  });

  for (var i = 0; i < _parts.length; i++) {
    final part = _parts[i];
    test('${part.heading}: its licence text is word for word', () {
      final block = squash(blocks[i]);
      expect(part.lines, isNotEmpty);
      for (final line in part.lines) {
        expect(block, contains(squash(line)), reason: line);
      }
    });

    for (final file in part.files) {
      test('${part.heading}: names its source $file at tag $_tag', () {
        expect(blocks[i], contains('Text of $file, lines '));
      });
    }
  }

  test('the notice names the project, the tag and what was left out', () {
    expect(notice, contains('github.com/utelle/SQLite3MultipleCiphers'));
    expect(notice, contains('tag $_tag'));
    expect(notice, contains('word for word'));
  });

  test('the intro says decorative comment lines were left out too', () {
    // M1.9a round 6: rijndael.c (lines 14 to 44) and miniz.c (lines 2 to 26)
    // each have one line made only of comment characters (a "///" opener, a
    // row of "*") that is not quoted. The intro must not claim that only the
    // comment marks at the start of lines were left out.
    final intro = notice
        .split('\n')
        .firstWhere((l) => l.contains('word for word'));
    expect(intro, contains('comment marks at the start of lines'));
    expect(intro, contains('decorative lines made only of comment characters'));
  });

  test('the MIT text is in the notice for the project and for miniz', () {
    // Not just once: miniz has its own copyright holders.
    final text = squash(notice);
    for (final paragraph in _mit) {
      expect(
        RegExp(RegExp.escape(squash(paragraph))).allMatches(text).length,
        2,
        reason: paragraph.substring(0, 40),
      );
    }
  });

  test('no part quotes text from a file it does not name', () {
    // Every "Text of <path>, lines a to b" is a path some part lists.
    final named = {for (final p in _parts) ...p.files};
    final quoted = RegExp(
      r'Text of (\S+), lines \d+ to \d+',
    ).allMatches(notice).map((m) => m.group(1)!).toSet();
    expect(quoted, named);
  });

  group('Argon2: Kusunga takes the CC0 1.0 option', () {
    // PM decision 2026-11-23 (docs/status.md): "Add the CC0 sentence". Argon2
    // is CC0-1.0 OR Apache-2.0; the notice says which one Kusunga uses, and
    // carries neither full licence text.
    const choice = 'Kusunga uses Argon2 under the CC0 1.0 option.';

    /// The quoted header, word for word and line for line, from its
    /// "Text of" line to its last line.
    const header = [
      '  Text of src/argon2/src/argon2.c, lines 1 to 16 (every file under '
          'src/argon2/src, src/argon2/src/blake2/blake2b.c included, opens '
          'with the same text):',
      '',
      '    Argon2 reference source code package - reference C implementations',
      '',
      '    Copyright 2015',
      '    Daniel Dinu, Dmitry Khovratovich, Jean-Philippe Aumasson, and '
          'Samuel Neves',
      '',
      '    You may use this work under the terms of a Creative Commons CC0 1.0',
      '    License/Waiver or the Apache Public License 2.0, at your option. '
          'The terms of',
      '    these licenses can be found at:',
      '',
      '    - CC0 1.0 Universal : https://creativecommons.org/publicdomain/zero/1.0',
      '    - Apache 2.0        : https://www.apache.org/licenses/LICENSE-2.0',
      '',
      '    You should have received a copy of both of these licenses along '
          'with this',
      '    software. If not, they may be obtained at the above URLs.',
    ];

    String argon2() => blocks.firstWhere((b) => b.startsWith('* Argon2 ('));

    test('the Argon2 part states the CC0 1.0 choice, outside the quote', () {
      final lines = argon2().split('\n');
      final said = lines.indexOf('  $choice');
      expect(said, isNot(-1), reason: 'the choice is its own line');
      expect(
        said,
        lessThan(lines.indexWhere((l) => l.startsWith('  Text of '))),
        reason: 'the choice is not inside the quoted header',
      );
      expect(RegExp(RegExp.escape(choice)).allMatches(notice), hasLength(1));
    });

    test('the quoted Argon2 header is unchanged', () {
      expect(argon2(), contains(header.join('\n')));
    });

    test('neither full licence text was added', () {
      final text = squash(notice);
      // Apache-2.0 section headings and the CC0 1.0 legal code's own words.
      for (final phrase in [
        'TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION',
        'Grant of Copyright License',
        'Statement of Purpose',
        'Public License Fallback',
      ]) {
        expect(text, isNot(contains(phrase)), reason: phrase);
      }
    });
  });
}
