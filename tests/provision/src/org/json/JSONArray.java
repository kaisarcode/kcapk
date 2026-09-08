package org.json;

import java.util.ArrayList;
import java.util.List;

public class JSONArray {
    private final List<Object> values;

    public JSONArray() {
        values = new ArrayList<Object>();
    }

    public JSONArray(String source) throws JSONException {
        Object parsed = Json.parse(source);
        if (!(parsed instanceof JSONArray)) {
            throw new JSONException("not a JSON array");
        }
        values = ((JSONArray) parsed).values;
    }

    JSONArray(List<Object> values) {
        this.values = values;
    }

    public int length() {
        return values.size();
    }

    public Object opt(int index) {
        return (index >= 0 && index < values.size()) ? values.get(index) : null;
    }

    public JSONObject getJSONObject(int index) throws JSONException {
        Object v = opt(index);
        if (v instanceof JSONObject) {
            return (JSONObject) v;
        }
        throw new JSONException("JSONArray[" + index + "] is not a JSONObject");
    }

    public JSONObject optJSONObject(int index) {
        Object v = opt(index);
        return (v instanceof JSONObject) ? (JSONObject) v : null;
    }

    public String getString(int index) throws JSONException {
        Object v = opt(index);
        if (v == null) {
            throw new JSONException("JSONArray[" + index + "] not found");
        }
        return String.valueOf(v);
    }

    public long getLong(int index) throws JSONException {
        Object v = opt(index);
        if (v instanceof Number) {
            return ((Number) v).longValue();
        }
        throw new JSONException("JSONArray[" + index + "] is not a number");
    }

    void put(Object value) {
        values.add(value);
    }

    List<Object> toList() {
        return values;
    }

    @Override
    public String toString() {
        StringBuilder sb = new StringBuilder();
        Json.quoteJoin(sb, values);
        return sb.toString();
    }
}