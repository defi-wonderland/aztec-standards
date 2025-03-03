pub mod StorageUtils {
    // NOTE: accepts arbitrary type T but does nothing with it
    pub fn public_storage_dependant_fn<T>(_storage: T) {}
}
