//! hello: the app docs/getting_started.md builds. A line of text and a
//! counter that goes up by itself; a key shows its character and space sets
//! the counter back to 0, q ends the app.
#![no_std]

use fmrb::{Event, Text, WINDOW};

#[derive(Default)]
struct Hello {
    count: i64,
    key: Text<8>,
    bg: i32,
    fg: i32,
}

impl fmrb::App for Hello {
    fn on_create(&mut self) {
        self.bg = fmrb::rgb(255, 255, 255); // white paper (never 0x01: the transparent key)
        self.fg = fmrb::rgb(0, 0, 0);
        self.key = Text::from("-");
        fmrb::log::info("hello: started");
    }

    fn on_update(&mut self) -> i32 {
        self.count += 1;
        let g = WINDOW;
        g.fill_rect(0, 0, g.area_width(), g.area_height(), self.bg);
        g.draw_text(4, 4, "Hello, Family mruby!", self.fg);
        g.draw_text(4, 16, Text::<32>::from("count ").int(self.count).as_str(), self.fg);
        g.draw_text(
            4,
            28,
            Text::<32>::from("key   ").push(self.key.as_str()).as_str(),
            self.fg,
        );
        g.present();
        100 // call me again in 100 ms
    }

    fn on_event(&mut self, ev: &Event) {
        if ev.kind() != fmrb::KEY_DOWN || ev.character == 0 {
            return;
        }
        match char::from_u32(ev.character as u32) {
            Some('q') => fmrb::app::stop(),
            Some(' ') => {
                self.count = 0;
                self.key = Text::from("space");
            }
            Some(c) => {
                self.key.clear().push_char(c);
            }
            None => {}
        }
    }

    fn on_destroy(&mut self) {
        fmrb::log::info(Text::<48>::from("hello: bye at count ").int(self.count).as_str());
    }
}

fmrb::app!(Hello);
