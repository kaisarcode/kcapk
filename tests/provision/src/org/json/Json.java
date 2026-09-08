package org.json;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

final class Json {
    private final String src;
    private int pos;

    private Json(String src) {
        this.src = src;
        this.pos = 0;
    }

    static Object parse(String source) throws JSONException {
        if (source == null || source.length() == 0) {
            throw new JSONException("empty JSON source");
        }
        Json p = new Json(source);
        p.skipWhitespace();
        Object value = p.parseValue();
        p.skipWhitespace();
        if (p.pos < source.length()) {
            throw new JSONException("trailing characters at offset " + p.pos);
        }
        return value;
    }

    private void skipWhitespace() {
        while (pos < src.length()) {
            char c = src.charAt(pos);
            if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
                pos++;
            } else {
                break;
            }
        }
    }

    private char peek() throws JSONException {
        if (pos >= src.length()) {
            throw new JSONException("unexpected end of input");
        }
        return src.charAt(pos);
    }

    private void expect(char c) throws JSONException {
        if (peek() != c) {
            throw new JSONException("expected '" + c + "' at offset " + pos);
        }
        pos++;
    }

    private Object parseValue() throws JSONException {
        char c = peek();
        switch (c) {
            case '{':
                return new JSONObject(parseObject());
            case '[':
                return new JSONArray(parseArray());
            case '"':
                return parseString();
            case 't':
                expectLiteral("true");
                return Boolean.TRUE;
            case 'f':
                expectLiteral("false");
                return Boolean.FALSE;
            case 'n':
                expectLiteral("null");
                return null;
            default:
                if (c == '-' || (c >= '0' && c <= '9')) {
                    return parseNumber();
                }
                throw new JSONException("unexpected character '" + c + "' at offset " + pos);
        }
    }

    private void expectLiteral(String lit) throws JSONException {
        for (int i = 0; i < lit.length(); i++) {
            if (peek() != lit.charAt(i)) {
                throw new JSONException("invalid literal at offset " + pos);
            }
            pos++;
        }
    }

    private Object parseNumber() throws JSONException {
        int start = pos;
        boolean decimal = false;
        if (pos < src.length() && src.charAt(pos) == '-') {
            pos++;
        }
        while (pos < src.length()) {
            char c = src.charAt(pos);
            if (c >= '0' && c <= '9') {
                pos++;
            } else if (c == '.' || c == 'e' || c == 'E' || c == '+' || c == '-') {
                decimal = true;
                pos++;
            } else {
                break;
            }
        }
        if (pos < src.length() && src.charAt(pos) == 'e') {
            pos++;
        }
        String token = src.substring(start, pos);
        try {
            if (decimal) {
                return Double.parseDouble(token);
            }
            return Long.parseLong(token);
        } catch (NumberFormatException e) {
            throw new JSONException("invalid number at offset " + start);
        }
    }

    private String parseString() throws JSONException {
        expect('"');
        StringBuilder sb = new StringBuilder();
        while (pos < src.length()) {
            char c = src.charAt(pos);
            if (c == '"') {
                pos++;
                return sb.toString();
            }
            if (c == '\\') {
                pos++;
                if (pos >= src.length()) {
                    throw new JSONException("unterminated escape");
                }
                char e = src.charAt(pos);
                pos++;
                switch (e) {
                    case '"': sb.append('"'); break;
                    case '\\': sb.append('\\'); break;
                    case '/': sb.append('/'); break;
                    case 'b': sb.append('\b'); break;
                    case 'f': sb.append('\f'); break;
                    case 'n': sb.append('\n'); break;
                    case 'r': sb.append('\r'); break;
                    case 't': sb.append('\t'); break;
                    case 'u': {
                        if (pos + 4 > src.length()) {
                            throw new JSONException("bad unicode escape");
                        }
                        String hex = src.substring(pos, pos + 4);
                        try {
                            sb.append((char) Integer.parseInt(hex, 16));
                        } catch (NumberFormatException ex) {
                            throw new JSONException("bad unicode escape");
                        }
                        pos += 4;
                        break;
                    }
                    default:
                        throw new JSONException("invalid escape '\\" + e + "'");
                }
            } else {
                sb.append(c);
                pos++;
            }
        }
        throw new JSONException("unterminated string");
    }

    private Map<String, Object> parseObject() throws JSONException {
        expect('{');
        Map<String, Object> map = new LinkedHashMap<String, Object>();
        skipWhitespace();
        if (peek() == '}') {
            pos++;
            return map;
        }
        while (true) {
            skipWhitespace();
            String key = parseString();
            skipWhitespace();
            expect(':');
            skipWhitespace();
            map.put(key, parseValue());
            skipWhitespace();
            char c = peek();
            if (c == ',') {
                pos++;
            } else if (c == '}') {
                pos++;
                return map;
            } else {
                throw new JSONException("expected ',' or '}' at offset " + pos);
            }
        }
    }

    private List<Object> parseArray() throws JSONException {
        expect('[');
        List<Object> list = new ArrayList<Object>();
        skipWhitespace();
        if (peek() == ']') {
            pos++;
            return list;
        }
        while (true) {
            skipWhitespace();
            list.add(parseValue());
            skipWhitespace();
            char c = peek();
            if (c == ',') {
                pos++;
            } else if (c == ']') {
                pos++;
                return list;
            } else {
                throw new JSONException("expected ',' or ']' at offset " + pos);
            }
        }
    }

    static String quoteObject(Map<String, Object> values) {
        StringBuilder sb = new StringBuilder();
        sb.append('{');
        boolean first = true;
        for (Map.Entry<String, Object> e : values.entrySet()) {
            if (!first) {
                sb.append(',');
            }
            first = false;
            quoteString(sb, e.getKey());
            sb.append(':');
            quoteValue(sb, e.getValue());
        }
        sb.append('}');
        return sb.toString();
    }

    static void quoteJoin(StringBuilder sb, List<Object> values) {
        sb.append('[');
        boolean first = true;
        for (Object v : values) {
            if (!first) {
                sb.append(',');
            }
            first = false;
            quoteValue(sb, v);
        }
        sb.append(']');
    }

    static void quoteValue(StringBuilder sb, Object v) {
        if (v == null) {
            sb.append("null");
        } else if (v instanceof String) {
            quoteString(sb, (String) v);
        } else if (v instanceof Boolean) {
            sb.append(v);
        } else if (v instanceof Number) {
            if (v instanceof Double || v instanceof Float) {
                double d = ((Number) v).doubleValue();
                if (d == Math.floor(d) && !Double.isInfinite(d) && Math.abs(d) < 1e15) {
                    sb.append((long) d);
                } else {
                    sb.append(d);
                }
            } else {
                sb.append(v);
            }
        } else if (v instanceof JSONObject) {
            sb.append(quoteObject(((JSONObject) v).toMap()));
        } else if (v instanceof JSONArray) {
            quoteJoin(sb, ((JSONArray) v).toList());
        } else {
            quoteString(sb, String.valueOf(v));
        }
    }

    static void quoteString(StringBuilder sb, String s) {
        sb.append('"');
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"': sb.append("\\\""); break;
                case '\\': sb.append("\\\\"); break;
                case '\n': sb.append("\\n"); break;
                case '\r': sb.append("\\r"); break;
                case '\t': sb.append("\\t"); break;
                case '\b': sb.append("\\b"); break;
                case '\f': sb.append("\\f"); break;
                default:
                    if (c < 0x20) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
            }
        }
        sb.append('"');
    }
}