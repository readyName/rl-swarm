    def train(self):
        try:
            self._train()

        except Exception:
            self.logger.error("Encountered error during training!")
            print_system_info()
            traceback.print_exc()
            raise

        ##################
        # ✅ 训练结束清理资源
        ##################
        self.logger.info("✅ 训练完成，开始清理资源...")
        try:
            del self.model
            del self.tokenizer
            # 如果 trainer 实例还在内存中，也一并清除（视调用逻辑）
            if hasattr(self, "trainer"):
                del self.trainer
        except Exception as e:
            self.logger.warning(f"资源清理时发生错误: {e}")

        import gc
        gc.collect()

        if torch.cuda.is_available():
            torch.cuda.empty_cache()
            torch.cuda.ipc_collect()
            self.logger.info("🧹 CUDA 显存清理完成")
        if torch.backends.mps.is_available():  # type: ignore
            try:
                torch.mps.empty_cache()  # type: ignore
                self.logger.info("🧹 MPS 显存清理完成")
            except Exception as e:
                self.logger.warning(f"⚠️ MPS 清理失败: {e}")
        try:
            if torch.xpu.is_available():  # type: ignore
                torch.xpu.empty_cache()  # type: ignore
                self.logger.info("🧹 XPU 显存清理完成")
        except AttributeError:
            pass

        self.logger.info("🧹 所有资源已清理完毕。")
