# Dmas Linux Termux Desktop

# Giới thiệu
- Linux được tạo bởi Nguyễn Tấn Dũng
- Nó tận dụng tài nguyên của một thiết bị đã bỏ đi làm linux
- Bạn cũng có thể dùng để làm server đơn giản như cho mai cồ ráp (Minecraft) hoặc dự án nhẹ
- Nó dùng proot-distro để dùng ubuntu, debian, fedora, v.v tại termux

# Cài đặt
- Tải Termux-X11 tại đây: [Termux-X11](https://github.com/termux/termux-x11/releases/tag/nightly)
- Cài đặt Termux bản mới nhất trên [F-droid](https://f-droid.org): [Termux F-droid](https://f-droid.org/en/packages/com.termux/)
- Cài đặt Termux bản mới nhất trên [Github](https://github.com): [Termux Github](https://github.com/termux/termux-app/releases)

- Cài đặt dự án về máy: [DmasLinux](https://github.com/dmasntd/DmasLinux/archive/refs/heads/main.zip)

# Triển khai
- Giải nén ra và di chuyển termux vào nơi chưa script setup

  ```bash
  bash linuxdmas.sh
  ```

- Chỉ cần nhập lệnh trên nó sẽ tự động cài đặt cho bạn và tự mở Termux-X11 cho bạn còn lại bạn chỉ cần tận hưởng và trải nhiệm
> Lưu ý: Nó cài kha khá nhiều giao diện và 1 số thứ có thể rất lâu và nó phụ thuộc vào mạng Wifi và Chip xử lý lên có thể hơi lâu

- Tôi sẽ cố gắng nâng cấp và xử lý làm sao để có thể giải quyết vấn đề này nhanh nhất có thể

# Lưu ý
- Các máy đời thấp RAM 4GB trở xuống các bạn lên root và cài module ZRAM để dùng
- Đa số máy đời thấp sẽ được coi là máy bỏ đi nó khá ít RAM các bạn mở 2 app trở nên sẽ tràn
- Nên dùng root và ZRAM để có không gian bộ nhớ làm việc
- Nếu muốn buil server cao hơn cũng cần đến root
- Nó không thể thay thế thành máy tính thật được và nó giới hạn xử lý theo chip
- Nên chạy dự án nhẹ vừa đủ 
  
