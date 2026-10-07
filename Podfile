platform :ios, '18.5'

# MediaPipeはSwift Package Managerを公式サポートしていないためCocoaPodsで導入する
target 'VideoPicker' do
  use_frameworks!

  # 人物モードの顔検出に使用
  pod 'MediaPipeTasksVision', '0.10.21'

  # テストはアプリ本体にリンク済みのMediaPipeを使うので、モジュールの検索パスだけ引き継ぐ
  target 'VideoPickerTests' do
    inherit! :search_paths
  end
end

# MediaPipeのpodspecは検索パスだけを引き継いだターゲットにも -force_load を付けてしまう。
# テストバンドルにも計算グラフが入ると二重登録になり起動時にクラッシュするため取り除く。
post_install do |installer|
  installer.aggregate_targets.each do |target|
    next unless target.name == 'Pods-VideoPickerTests'

    target.user_build_configurations.each_key do |config_name|
      path = target.xcconfig_path(config_name)
      kept_lines = File.readlines(path)
        .reject { |line| line.start_with?('OTHER_LDFLAGS[sdk=') }
        .map { |line| line.gsub(/ -framework "MediaPipeTasks(Common|Vision)"/, '') }
      File.write(path, kept_lines.join)
    end
  end
end
