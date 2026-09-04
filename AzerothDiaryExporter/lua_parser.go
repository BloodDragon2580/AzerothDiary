package main

import (
	"fmt"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"
)

type luaTokenType int

const (
	tokEOF luaTokenType = iota
	tokIdent
	tokString
	tokNumber
	tokLBrace
	tokRBrace
	tokLBracket
	tokRBracket
	tokEqual
	tokComma
	tokSemi
)

type luaToken struct {
	typ luaTokenType
	val string
	pos int
}

type luaLexer struct {
	src string
	pos int
}

func (l *luaLexer) skipSpaceAndComments() {
	for l.pos < len(l.src) {
		r, size := utf8.DecodeRuneInString(l.src[l.pos:])
		if unicode.IsSpace(r) {
			l.pos += size
			continue
		}
		if strings.HasPrefix(l.src[l.pos:], "--") {
			l.pos += 2
			if strings.HasPrefix(l.src[l.pos:], "[[") {
				l.pos += 2
				if end := strings.Index(l.src[l.pos:], "]]"); end >= 0 {
					l.pos += end + 2
				} else {
					l.pos = len(l.src)
				}
			} else {
				for l.pos < len(l.src) && l.src[l.pos] != '\n' {
					l.pos++
				}
			}
			continue
		}
		break
	}
}

func (l *luaLexer) next() (luaToken, error) {
	l.skipSpaceAndComments()
	if l.pos >= len(l.src) {
		return luaToken{typ: tokEOF, pos: l.pos}, nil
	}
	start := l.pos
	c := l.src[l.pos]
	switch c {
	case '{':
		l.pos++
		return luaToken{typ: tokLBrace, val: "{", pos: start}, nil
	case '}':
		l.pos++
		return luaToken{typ: tokRBrace, val: "}", pos: start}, nil
	case '[':
		l.pos++
		return luaToken{typ: tokLBracket, val: "[", pos: start}, nil
	case ']':
		l.pos++
		return luaToken{typ: tokRBracket, val: "]", pos: start}, nil
	case '=':
		l.pos++
		return luaToken{typ: tokEqual, val: "=", pos: start}, nil
	case ',':
		l.pos++
		return luaToken{typ: tokComma, val: ",", pos: start}, nil
	case ';':
		l.pos++
		return luaToken{typ: tokSemi, val: ";", pos: start}, nil
	case '\'', '"':
		quote := c
		l.pos++
		var b strings.Builder
		for l.pos < len(l.src) {
			c = l.src[l.pos]
			if c == quote {
				l.pos++
				return luaToken{typ: tokString, val: b.String(), pos: start}, nil
			}
			if c != '\\' {
				r, size := utf8.DecodeRuneInString(l.src[l.pos:])
				b.WriteRune(r)
				l.pos += size
				continue
			}
			l.pos++
			if l.pos >= len(l.src) {
				break
			}
			esc := l.src[l.pos]
			l.pos++
			switch esc {
			case 'a':
				b.WriteByte('\a')
			case 'b':
				b.WriteByte('\b')
			case 'f':
				b.WriteByte('\f')
			case 'n':
				b.WriteByte('\n')
			case 'r':
				b.WriteByte('\r')
			case 't':
				b.WriteByte('\t')
			case 'v':
				b.WriteByte('\v')
			case '\\':
				b.WriteByte('\\')
			case '"':
				b.WriteByte('"')
			case '\'':
				b.WriteByte('\'')
			case '\n':
			case 'z':
				for l.pos < len(l.src) {
					r, size := utf8.DecodeRuneInString(l.src[l.pos:])
					if !unicode.IsSpace(r) {
						break
					}
					l.pos += size
				}
			case 'x':
				if l.pos+2 <= len(l.src) {
					if v, err := strconv.ParseUint(l.src[l.pos:l.pos+2], 16, 8); err == nil {
						b.WriteByte(byte(v))
						l.pos += 2
					}
				}
			default:
				if esc >= '0' && esc <= '9' {
					digits := []byte{esc}
					for len(digits) < 3 && l.pos < len(l.src) && l.src[l.pos] >= '0' && l.src[l.pos] <= '9' {
						digits = append(digits, l.src[l.pos])
						l.pos++
					}
					if v, err := strconv.ParseUint(string(digits), 10, 8); err == nil {
						b.WriteByte(byte(v))
					}
				} else {
					b.WriteByte(esc)
				}
			}
		}
		return luaToken{}, fmt.Errorf("unterminated string at %d", start)
	}

	if (c >= '0' && c <= '9') || c == '-' || c == '+' || c == '.' {
		l.pos++
		for l.pos < len(l.src) {
			ch := l.src[l.pos]
			if (ch >= '0' && ch <= '9') || ch == '.' || ch == 'e' || ch == 'E' || ch == '+' || ch == '-' {
				l.pos++
			} else {
				break
			}
		}
		return luaToken{typ: tokNumber, val: l.src[start:l.pos], pos: start}, nil
	}
	if c == '_' || unicode.IsLetter(rune(c)) {
		l.pos++
		for l.pos < len(l.src) {
			r, size := utf8.DecodeRuneInString(l.src[l.pos:])
			if r == '_' || unicode.IsLetter(r) || unicode.IsDigit(r) {
				l.pos += size
			} else {
				break
			}
		}
		return luaToken{typ: tokIdent, val: l.src[start:l.pos], pos: start}, nil
	}
	return luaToken{}, fmt.Errorf("unexpected character %q at %d", c, start)
}

type LuaTable struct {
	Array []any
	Str   map[string]any
	Num   map[int]any
}

func newLuaTable() *LuaTable { return &LuaTable{Str: map[string]any{}, Num: map[int]any{}} }

func (t *LuaTable) put(key any, value any) {
	if key == nil {
		t.Array = append(t.Array, value)
		return
	}
	switch k := key.(type) {
	case string:
		t.Str[k] = value
	case int:
		t.Num[k] = value
	case int64:
		t.Num[int(k)] = value
	case float64:
		if k == float64(int(k)) {
			t.Num[int(k)] = value
		} else {
			t.Str[fmt.Sprint(k)] = value
		}
	default:
		t.Str[fmt.Sprint(k)] = value
	}
}

func (t *LuaTable) Get(key string) any {
	if t == nil {
		return nil
	}
	return t.Str[key]
}
func (t *LuaTable) GetTable(key string) *LuaTable { v, _ := t.Get(key).(*LuaTable); return v }
func (t *LuaTable) GetString(key string) string {
	if v := t.Get(key); v != nil {
		if s, ok := v.(string); ok {
			return s
		}
		return fmt.Sprint(v)
	}
	return ""
}
func (t *LuaTable) GetFloat(key string) float64 { return anyFloat(t.Get(key)) }
func (t *LuaTable) GetBool(key string) bool     { v := t.Get(key); b, _ := v.(bool); return b }
func (t *LuaTable) Values() []any {
	out := append([]any{}, t.Array...)
	if len(t.Num) > 0 {
		max := 0
		for k := range t.Num {
			if k > max {
				max = k
			}
		}
		for i := 1; i <= max; i++ {
			if v, ok := t.Num[i]; ok {
				out = append(out, v)
			}
		}
	}
	return out
}

type luaParser struct {
	lex *luaLexer
	cur luaToken
	has bool
}

func (p *luaParser) peek() (luaToken, error) {
	if p.has {
		return p.cur, nil
	}
	t, e := p.lex.next()
	if e == nil {
		p.cur = t
		p.has = true
	}
	return t, e
}
func (p *luaParser) take() (luaToken, error) { t, e := p.peek(); p.has = false; return t, e }
func (p *luaParser) expect(tt luaTokenType) (luaToken, error) {
	t, e := p.take()
	if e != nil {
		return t, e
	}
	if t.typ != tt {
		return t, fmt.Errorf("expected token %d at %d, got %d (%q)", tt, t.pos, t.typ, t.val)
	}
	return t, nil
}

func ParseSavedVariables(src string) (*LuaTable, error) {
	p := &luaParser{lex: &luaLexer{src: src}}
	// Find AzerothDiaryDB assignment, but tolerate a file containing only a table.
	for {
		t, err := p.peek()
		if err != nil {
			return nil, err
		}
		if t.typ == tokEOF {
			return nil, fmt.Errorf("AzerothDiaryDB not found")
		}
		if t.typ == tokLBrace {
			v, err := p.parseValue()
			if err != nil {
				return nil, err
			}
			tbl, ok := v.(*LuaTable)
			if !ok {
				return nil, fmt.Errorf("root is not a table")
			}
			return tbl, nil
		}
		if t.typ == tokIdent {
			ident, _ := p.take()
			eq, err := p.peek()
			if err != nil {
				return nil, err
			}
			if ident.val == "AzerothDiaryDB" && eq.typ == tokEqual {
				_, _ = p.take()
				v, err := p.parseValue()
				if err != nil {
					return nil, err
				}
				tbl, ok := v.(*LuaTable)
				if !ok {
					return nil, fmt.Errorf("AzerothDiaryDB is not a table")
				}
				return tbl, nil
			}
			continue
		}
		_, _ = p.take()
	}
}

func (p *luaParser) parseValue() (any, error) {
	t, err := p.take()
	if err != nil {
		return nil, err
	}
	switch t.typ {
	case tokString:
		return t.val, nil
	case tokNumber:
		if i, e := strconv.ParseInt(t.val, 10, 64); e == nil {
			return i, nil
		}
		if f, e := strconv.ParseFloat(t.val, 64); e == nil {
			return f, nil
		}
		return nil, fmt.Errorf("invalid number %q at %d", t.val, t.pos)
	case tokIdent:
		switch t.val {
		case "true":
			return true, nil
		case "false":
			return false, nil
		case "nil":
			return nil, nil
		default:
			return t.val, nil
		}
	case tokLBrace:
		return p.parseTable()
	default:
		return nil, fmt.Errorf("unexpected token %d (%q) at %d", t.typ, t.val, t.pos)
	}
}

func (p *luaParser) parseTable() (*LuaTable, error) {
	tbl := newLuaTable()
	for {
		t, err := p.peek()
		if err != nil {
			return nil, err
		}
		if t.typ == tokRBrace {
			_, _ = p.take()
			return tbl, nil
		}
		if t.typ == tokEOF {
			return nil, fmt.Errorf("unterminated table")
		}
		var key any
		var value any
		if t.typ == tokLBracket {
			_, _ = p.take()
			key, err = p.parseValue()
			if err != nil {
				return nil, err
			}
			if _, err = p.expect(tokRBracket); err != nil {
				return nil, err
			}
			if _, err = p.expect(tokEqual); err != nil {
				return nil, err
			}
			value, err = p.parseValue()
			if err != nil {
				return nil, err
			}
		} else if t.typ == tokIdent {
			ident, _ := p.take()
			nxt, err := p.peek()
			if err != nil {
				return nil, err
			}
			if nxt.typ == tokEqual {
				_, _ = p.take()
				key = ident.val
				value, err = p.parseValue()
				if err != nil {
					return nil, err
				}
			} else {
				p.cur = ident
				p.has = true
				value, err = p.parseValue()
				if err != nil {
					return nil, err
				}
			}
		} else {
			value, err = p.parseValue()
			if err != nil {
				return nil, err
			}
		}
		tbl.put(key, value)
		sep, err := p.peek()
		if err != nil {
			return nil, err
		}
		if sep.typ == tokComma || sep.typ == tokSemi {
			_, _ = p.take()
		}
	}
}

func anyFloat(v any) float64 {
	switch n := v.(type) {
	case int:
		return float64(n)
	case int64:
		return float64(n)
	case float64:
		return n
	case string:
		f, _ := strconv.ParseFloat(n, 64)
		return f
	}
	return 0
}
func anyInt(v any) int64 { return int64(anyFloat(v)) }
