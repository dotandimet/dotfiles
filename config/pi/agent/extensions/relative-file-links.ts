import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

type LinkResolution =
  | { kind: "external" }
  | { kind: "file"; href: string }
  | { kind: "unresolved"; displayHref: string };

type ReferenceDefinition = {
  resolution: LinkResolution;
};

type ParsedDestination = {
  hrefStart: number;
  hrefEnd: number;
  href: string;
  fullEnd?: number;
};

type AnalyzedLine = {
  content: string;
  ending: string;
  excluded: boolean;
  definition?: {
    id: string;
    destination: ParsedDestination;
  };
};

const SCHEME = /^[a-z][a-z\d+.-]*:/i;
const REFERENCE_DEFINITION = /^ {0,3}\[((?:\\.|[^\]\\])+)\]:[ \t]*/;
const FENCE_OPEN = /^ {0,3}(`{3,}|~{3,})/;

function isEscaped(text: string, index: number): boolean {
  let backslashes = 0;
  for (let cursor = index - 1; cursor >= 0 && text[cursor] === "\\"; cursor--) {
    backslashes++;
  }
  return backslashes % 2 === 1;
}

function decodeMarkdownHref(href: string): string {
  return href
    .replace(/\\([!"#$%&'()*+,\-./:;<=>?@[\\\]^_`{|}~ ])/g, "$1")
    .replace(/&amp;/gi, "&")
    .replace(/&#(\d+);/g, (_match, decimal: string) => String.fromCodePoint(Number.parseInt(decimal, 10)))
    .replace(/&#x([\da-f]+);/gi, (_match, hex: string) => String.fromCodePoint(Number.parseInt(hex, 16)));
}

function firstUnescapedSuffixIndex(href: string): number {
  for (let index = 0; index < href.length; index++) {
    if ((href[index] === "?" || href[index] === "#") && !isEscaped(href, index)) {
      return index;
    }
  }
  return -1;
}

function resolveHref(rawHref: string, cwd: string): LinkResolution {
  const decodedHref = decodeMarkdownHref(rawHref);

  if (
    decodedHref.startsWith("#") ||
    decodedHref.startsWith("?") ||
    decodedHref.startsWith("//") ||
    (!isAbsolute(decodedHref) && SCHEME.test(decodedHref))
  ) {
    return { kind: "external" };
  }

  const suffixIndex = firstUnescapedSuffixIndex(rawHref);
  const rawPath = suffixIndex >= 0 ? rawHref.slice(0, suffixIndex) : rawHref;
  const rawSuffix = suffixIndex >= 0 ? rawHref.slice(suffixIndex) : "";
  let pathname = decodeMarkdownHref(rawPath);

  try {
    pathname = decodeURIComponent(pathname);
  } catch {
    // Keep malformed percent escapes visible rather than throwing during rendering.
  }

  if (!pathname) {
    return { kind: "external" };
  }

  let absolutePath: string;
  if (pathname === "~" || pathname.startsWith("~/")) {
    absolutePath = resolve(homedir(), pathname === "~" ? "." : pathname.slice(2));
  } else {
    absolutePath = isAbsolute(pathname) ? pathname : resolve(cwd, pathname);
  }

  if (!existsSync(absolutePath)) {
    return { kind: "unresolved", displayHref: decodedHref };
  }

  const url = pathToFileURL(absolutePath);
  if (rawSuffix) {
    const decodedSuffix = decodeMarkdownHref(rawSuffix);
    const hashIndex = decodedSuffix.indexOf("#");
    const search = hashIndex >= 0 ? decodedSuffix.slice(0, hashIndex) : decodedSuffix;
    const hash = hashIndex >= 0 ? decodedSuffix.slice(hashIndex) : "";
    if (search.startsWith("?")) url.search = search;
    if (hash.startsWith("#")) url.hash = hash;
  }

  return { kind: "file", href: url.href };
}

function normalizeReferenceId(id: string): string {
  return decodeMarkdownHref(id).trim().replace(/\s+/g, " ").toLowerCase();
}

function parseDefinitionDestination(text: string, start: number): ParsedDestination | undefined {
  if (start >= text.length) return undefined;

  if (text[start] === "<") {
    for (let index = start + 1; index < text.length; index++) {
      if (text[index] === ">" && !isEscaped(text, index)) {
        return {
          hrefStart: start + 1,
          hrefEnd: index,
          href: text.slice(start + 1, index),
        };
      }
    }
    return undefined;
  }

  let index = start;
  while (index < text.length) {
    if (text[index] === "\\" && index + 1 < text.length) {
      index += 2;
      continue;
    }
    if (/\s/.test(text[index])) break;
    index++;
  }

  if (index === start) return undefined;
  return {
    hrefStart: start,
    hrefEnd: index,
    href: text.slice(start, index),
  };
}

function findQuotedEnd(text: string, start: number, closing: string): number | undefined {
  let depth = 0;
  for (let index = start + 1; index < text.length; index++) {
    if (text[index] === "\\" && index + 1 < text.length) {
      index++;
      continue;
    }
    if (closing === ")" && text[index] === "(") {
      depth++;
      continue;
    }
    if (text[index] === closing) {
      if (depth > 0) {
        depth--;
      } else {
        return index;
      }
    }
  }
  return undefined;
}

function findInlineLinkEnd(text: string, afterDestination: number): number | undefined {
  let cursor = afterDestination;
  while (cursor < text.length && /\s/.test(text[cursor])) cursor++;
  if (text[cursor] === ")") return cursor;

  const opening = text[cursor];
  const closing = opening === "(" ? ")" : opening;
  if (opening !== '"' && opening !== "'" && opening !== "(") return undefined;

  const titleEnd = findQuotedEnd(text, cursor, closing);
  if (titleEnd === undefined) return undefined;
  cursor = titleEnd + 1;
  while (cursor < text.length && /\s/.test(text[cursor])) cursor++;
  return text[cursor] === ")" ? cursor : undefined;
}

function parseInlineDestination(text: string, openParen: number): ParsedDestination | undefined {
  let cursor = openParen + 1;
  while (cursor < text.length && /\s/.test(text[cursor])) cursor++;
  if (text[cursor] === ")") return undefined;

  if (text[cursor] === "<") {
    const hrefStart = cursor + 1;
    for (let index = hrefStart; index < text.length; index++) {
      if (text[index] === ">" && !isEscaped(text, index)) {
        const closeParen = findInlineLinkEnd(text, index + 1);
        if (closeParen === undefined) return undefined;
        return {
          hrefStart,
          hrefEnd: index,
          href: text.slice(hrefStart, index),
          fullEnd: closeParen + 1,
        };
      }
    }
    return undefined;
  }

  const hrefStart = cursor;
  let nestedParentheses = 0;
  while (cursor < text.length) {
    const character = text[cursor];
    if (character === "\\" && cursor + 1 < text.length) {
      cursor += 2;
      continue;
    }
    if (character === "(") {
      nestedParentheses++;
      cursor++;
      continue;
    }
    if (character === ")") {
      if (nestedParentheses === 0) {
        if (cursor === hrefStart) return undefined;
        return {
          hrefStart,
          hrefEnd: cursor,
          href: text.slice(hrefStart, cursor),
          fullEnd: cursor + 1,
        };
      }
      nestedParentheses--;
      cursor++;
      continue;
    }
    if (/\s/.test(character) && nestedParentheses === 0) {
      const closeParen = findInlineLinkEnd(text, cursor);
      if (closeParen === undefined || cursor === hrefStart) return undefined;
      return {
        hrefStart,
        hrefEnd: cursor,
        href: text.slice(hrefStart, cursor),
        fullEnd: closeParen + 1,
      };
    }
    cursor++;
  }

  return undefined;
}

function findClosingBracket(text: string, start: number): number | undefined {
  let depth = 0;
  for (let index = start + 1; index < text.length; index++) {
    if (text[index] === "\\" && index + 1 < text.length) {
      index++;
      continue;
    }
    if (text[index] === "[") {
      depth++;
      continue;
    }
    if (text[index] === "]") {
      if (depth > 0) {
        depth--;
      } else {
        return index;
      }
    }
  }
  return undefined;
}

function codeSpan(value: string): string {
  let longestRun = 0;
  for (const match of value.matchAll(/`+/g)) {
    longestRun = Math.max(longestRun, match[0].length);
  }
  const delimiter = "`".repeat(longestRun + 1);
  const needsPadding = value.startsWith("`") || value.endsWith("`") || value.startsWith(" ") || value.endsWith(" ");
  return `${delimiter}${needsPadding ? " " : ""}${value}${needsPadding ? " " : ""}${delimiter}`;
}

function visibleFallback(label: string, resolution: LinkResolution): string {
  if (resolution.kind !== "unresolved") return label;
  return `${label} (${codeSpan(resolution.displayHref)})`;
}

function rewriteInlineLinks(
  text: string,
  cwd: string,
  references: ReadonlyMap<string, ReferenceDefinition>,
): string {
  let result = "";
  let cursor = 0;

  while (cursor < text.length) {
    if (text[cursor] === "`" && !isEscaped(text, cursor)) {
      let runEnd = cursor + 1;
      while (text[runEnd] === "`") runEnd++;
      const delimiter = text.slice(cursor, runEnd);
      const closing = text.indexOf(delimiter, runEnd);
      if (closing < 0) {
        result += text.slice(cursor);
        break;
      }
      result += text.slice(cursor, closing + delimiter.length);
      cursor = closing + delimiter.length;
      continue;
    }

    if (text[cursor] !== "[" || isEscaped(text, cursor)) {
      result += text[cursor];
      cursor++;
      continue;
    }

    const labelEnd = findClosingBracket(text, cursor);
    if (labelEnd === undefined) {
      result += text[cursor];
      cursor++;
      continue;
    }

    const isImage = cursor > 0 && text[cursor - 1] === "!" && !isEscaped(text, cursor - 1);
    const label = text.slice(cursor + 1, labelEnd);
    const afterLabel = labelEnd + 1;

    if (!isImage && text[afterLabel] === "(") {
      const destination = parseInlineDestination(text, afterLabel);
      if (destination?.fullEnd !== undefined) {
        const resolution = resolveHref(destination.href, cwd);
        if (resolution.kind === "file") {
          result += text.slice(cursor, destination.hrefStart) + resolution.href + text.slice(destination.hrefEnd, destination.fullEnd);
        } else if (resolution.kind === "unresolved") {
          result += visibleFallback(label, resolution);
        } else {
          result += text.slice(cursor, destination.fullEnd);
        }
        cursor = destination.fullEnd;
        continue;
      }
    }

    if (!isImage && text[afterLabel] === "[") {
      const referenceEnd = findClosingBracket(text, afterLabel);
      if (referenceEnd !== undefined) {
        const rawId = text.slice(afterLabel + 1, referenceEnd) || label;
        const definition = references.get(normalizeReferenceId(rawId));
        if (definition?.resolution.kind === "unresolved") {
          result += visibleFallback(label, definition.resolution);
        } else {
          result += text.slice(cursor, referenceEnd + 1);
        }
        cursor = referenceEnd + 1;
        continue;
      }
    }

    if (!isImage) {
      const definition = references.get(normalizeReferenceId(label));
      if (definition?.resolution.kind === "unresolved") {
        result += visibleFallback(label, definition.resolution);
        cursor = afterLabel;
        continue;
      }
    }

    result += text.slice(cursor, afterLabel);
    cursor = afterLabel;
  }

  return result;
}

function splitLine(rawLine: string): { content: string; ending: string } {
  if (rawLine.endsWith("\r")) return { content: rawLine.slice(0, -1), ending: "\r" };
  return { content: rawLine, ending: "" };
}

function isFenceClose(line: string, marker: string): boolean {
  const match = /^ {0,3}(`+|~+)[ \t]*$/.exec(line);
  return !!match && match[1][0] === marker[0] && match[1].length >= marker.length;
}

function analyzeMarkdown(markdown: string, cwd: string): {
  lines: AnalyzedLine[];
  references: Map<string, ReferenceDefinition>;
} {
  const rawLines = markdown.split("\n");
  const lines: AnalyzedLine[] = [];
  const references = new Map<string, ReferenceDefinition>();
  let fence: string | undefined;

  for (let index = 0; index < rawLines.length; index++) {
    const { content, ending: carriageReturn } = splitLine(rawLines[index]);
    const ending = index < rawLines.length - 1 ? `${carriageReturn}\n` : carriageReturn;

    if (fence) {
      lines.push({ content, ending, excluded: true });
      if (isFenceClose(content, fence)) fence = undefined;
      continue;
    }

    const opening = FENCE_OPEN.exec(content)?.[1];
    if (opening) {
      fence = opening;
      lines.push({ content, ending, excluded: true });
      continue;
    }

    if (/^(?: {4}|\t)/.test(content)) {
      lines.push({ content, ending, excluded: true });
      continue;
    }

    const definitionMatch = REFERENCE_DEFINITION.exec(content);
    if (definitionMatch) {
      const destination = parseDefinitionDestination(content, definitionMatch[0].length);
      if (destination) {
        const id = normalizeReferenceId(definitionMatch[1]);
        const resolution = resolveHref(destination.href, cwd);
        references.set(id, { resolution });
        lines.push({ content, ending, excluded: false, definition: { id, destination } });
        continue;
      }
    }

    lines.push({ content, ending, excluded: false });
  }

  return { lines, references };
}

export function rewriteRelativeFileLinks(markdown: string, cwd: string): string {
  const { lines, references } = analyzeMarkdown(markdown, cwd);

  return lines
    .map((line) => {
      if (line.excluded) return line.content + line.ending;

      if (line.definition) {
        const definition = references.get(line.definition.id);
        if (definition?.resolution.kind === "file") {
          const { hrefStart, hrefEnd } = line.definition.destination;
          return line.content.slice(0, hrefStart) + definition.resolution.href + line.content.slice(hrefEnd) + line.ending;
        }
        return line.content + line.ending;
      }

      return rewriteInlineLinks(line.content, cwd, references) + line.ending;
    })
    .join("");
}

export default function relativeFileLinksExtension(pi: ExtensionAPI): void {
  let cwd = process.cwd();

  pi.on("session_start", (_event, ctx) => {
    cwd = ctx.cwd;
  });

  pi.registerMarkdownTransformer((markdown, { messageType }) => {
    if (messageType !== "assistant") return markdown;
    return rewriteRelativeFileLinks(markdown, cwd);
  });
}
