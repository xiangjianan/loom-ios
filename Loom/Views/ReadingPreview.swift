import Foundation

// Local UI fixtures, selected only with --demo. They never enter the user's saved history.
enum ReadingPreview {
    static let svg = #"""
    第一句，逗号、顿号和冒号：现在按标点分割。第二句可以独立高亮！第三句也可以吗？

    ```svg
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 300">
      <defs><linearGradient id="glass"><stop stop-color="#6756ef"/><stop offset="1" stop-color="#2daeff"/></linearGradient></defs>
      <rect x="10" y="10" width="580" height="280" rx="28" fill="url(#glass)"/>
      <path d="M150 120 H450 M150 180 H450" stroke="white" stroke-width="8" stroke-linecap="round"/>
      <circle cx="150" cy="150" r="48" fill="white"/><circle cx="450" cy="150" r="48" fill="white"/>
      <text x="300" y="260" text-anchor="middle" fill="white" font-size="28">Loom · SVG</text>
    </svg>
    ```

    图片后面的文字依然支持选择和高亮。
    """#
    static let long = (1...60).map { "第\($0)段：这是一段用于验证原生多行选择的文字。拖动选区手柄靠近阅读区域底部时，页面应该持续向下滚动，并继续选中下面的文字。" }.joined(separator: "\n\n")
}
