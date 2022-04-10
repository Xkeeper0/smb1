<?php

	// big regex mess to reformat the original disassembly
	// normalizes comments to column 50, capitalizes opcodes,
	// some other things that i somehow made regex do


	$inFile	= $argv[1] ?? null;
	if (!$inFile) {
		die("feed me a filename\n");
	}
	if (!file_exists($inFile)) {
		die("'$inFile' doesn't exist\n");
	}


	$lines	= explode("\n", file_get_contents($inFile));

	define('COMMENT_COL', 41);
	define('MAGIC_REGEX', '/^(?P<label>[A-Za-z0-9_]+:)? *(?P<opcode>\.?[a-z]{2,3})?(?P<etc> +[^;\n]+)?(?P<comment>;.*)?$/i');

	$y	= 0;
	$x	= 0;
	foreach ($lines as $line) {

		reformat($line);

	}


	function reformat($line) {

		$matches		= [];
		$n				= preg_match(MAGIC_REGEX, $line, $matches);

		if (isset($matches['label']) && $matches['label']) {
			print trim($matches['label']) ."\n";
			// very lazy
			// covertly remove the label
			$split		= explode(":", $line, 2);
			if ($split[1] ?? false) {
				reformat($split[1]);
			}
			return;
		}

		$m	= [
			'opcode'	=> $matches['opcode'] ?? null,
			'etc'		=> $matches['etc'] ?? null,
			'comment'	=> $matches['comment'] ?? null,
			];

		if ($m['opcode'] != ".db" && $m['opcode'] != ".dw") {
			$m['opcode']	= strtoupper($m['opcode']);
		}

		if ($m['comment'] && $m['comment'][0] == ";" && $m['comment'][1] != " ") {
			$m['comment'][0]	= " ";
			$m['comment']		= ";" . $m['comment'];
		}

		if ($m['opcode'] || $m['etc']) {
			$out	= sprintf("\t%-3s%-". COMMENT_COL ."s %s", $m['opcode'], $m['etc'], $m['comment']);
		} else {
			$out	= $m['comment'];
		}




		print rtrim($out) ."\n";


	}
