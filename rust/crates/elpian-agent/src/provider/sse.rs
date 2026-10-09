//! A server-sent-events reader: `event:` / `data:` lines, dispatched on a
//! blank line.

use std::io::BufRead;

/// One event.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SseEvent {
    pub event: String,
    pub data: String,
}

/// Read events from `reader`, calling `on_event` for each. Stops early when
/// `on_event` returns `false`.
pub fn read_events(
    reader: &mut dyn BufRead,
    on_event: &mut dyn FnMut(SseEvent) -> bool,
) -> std::io::Result<()> {
    let mut event = String::new();
    let mut data: Vec<String> = Vec::new();
    let mut line = String::new();
    loop {
        line.clear();
        let read = reader.read_line(&mut line)?;
        if read == 0 {
            // A final event without its blank line still counts.
            if !data.is_empty() {
                on_event(SseEvent {
                    event: std::mem::take(&mut event),
                    data: data.join("\n"),
                });
            }
            return Ok(());
        }
        let trimmed = line.trim_end_matches(['\n', '\r']);
        if trimmed.is_empty() {
            if !data.is_empty() || !event.is_empty() {
                let keep_going = on_event(SseEvent {
                    event: std::mem::take(&mut event),
                    data: data.join("\n"),
                });
                data.clear();
                if !keep_going {
                    return Ok(());
                }
            }
            continue;
        }
        if trimmed.starts_with(':') {
            continue; // a comment
        }
        let (field, value) = match trimmed.split_once(':') {
            Some((f, v)) => (f, v.strip_prefix(' ').unwrap_or(v)),
            None => (trimmed, ""),
        };
        match field {
            "event" => event = value.to_string(),
            "data" => data.push(value.to_string()),
            _ => {}
        }
    }
}
